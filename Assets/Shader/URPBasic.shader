Shader "Custom/URP/URPBasic"
{
    Properties
    {
        _BaseColor ("主颜色", Color) = (1, 1, 1, 1)
        _SpecColor ("高光颜色", Color) = (1, 1, 1, 1)
        _Shininess ("高光指数", Range(1, 128)) = 32
        _RimColor ("边缘光颜色", Color) = (1, 1, 1, 1)
        _RimPower ("边缘光强度", Range(0.1, 8))  = 2
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" // 归类为不透明 在URP中，不再影响渲染顺序
            "RenderPipeline" = "UniversalRenderPipeline" // URP专属标签
        }

        Pass
        {
            Name "ForwardLit" // 给这个Pass起的名字 其他SubShader可以引用这个Pass
            Tags
            {
                "LightMode" = "UniversalForward" // 向前渲染：绘制普通物体，计算所有光照

                // 常见 LightMode
                // "UniversalForward" 向前渲染：绘制普通物体，计算所有光照
                // “ShadowCaser” 阴影投射：从光源视角渲染深度图
                // "UniversalGBuffer" 延迟渲染：将几何信息写入GBuffer
                // "DepthOnly" 深度预渲染：生成深度纹理，用于后处理或不透明物体的深度写入
                // “Universal2D” 2D渲染：专门给2D Renderer使用
                // “SRPDefaultUnlit” 默认无光照：渲染不参与光照计算的物体（如UI、粒子）
            }

            HLSLPROGRAM // HLSL语法开始

            #pragma vertex vert
            #pragma fragment frag

            // 阴影接收编译宏
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS // 要不要让物体的影子落到其他东西上？
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE // 远处的影子要不要变模糊一点来节省性能？
            #pragma multi_compile _ _SHADOWS_SOFT // 影子的边缘是硬的还是软的？

            // 多光源必备宏
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _FORWARD_PLUS // Forward+ 渲染路径（URP 12+/Unity 6）
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS

            // URP 核心库
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;

                // 常见语义
                // POSITION : float4/float3 : 顶点位置（模型空间坐标）
                // NORMAL : float3 : 顶点法线（模型空间方向）
                // TEXCOORD0 ~ TEXCOORD7 : float2/float3/float4 : 纹理坐标（UV），可存多套UV或通用数据
                // TANGENT : float4 : 顶点切线（模型空间 .w存副法线方向符号）
                // COLOR : float4 顶点颜色
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION; // 系统值语义，它告诉GPU：这是顶点最终坐标，必须写入 CS：Clip Space
                float3 normalWS : TEXCOORD0; // 世界空间法线 TEXCOORD0是通用插值槽 通常用于传递自定义数据
                float3 positionWS : TEXCOORD1; // 第二个通用插值槽
                float4 shadowCoord : TEXCOORD2;
            };

            // 常量缓冲区 与Property一一对应
            // UnityPerMaterial 是这个常量缓冲区的名字
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _SpecColor;
                float _Shininess;
                float4 _RimColor;
                float _RimPower;
            CBUFFER_END

            Varyings vert (Attributes v)
            {
                Varyings o;

                // 物体空间 -> 世界空间
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);

                // 世界空间 -> 裁剪空间
                o.positionCS = TransformWorldToHClip(o.positionWS);

                // 法线转世界空间
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);

                // 计算当前顶点在光坐标系下的值
                o.shadowCoord = TransformWorldToShadowCoord(o.positionWS);

                return o;
            }

            float4 frag (Varyings i) : SV_Target // 系统值语义 这个函数的返回值 就是渲染目标的颜色
            {
                // 归一化
                float3 N = normalize(i.normalWS);

                // 获取主光
                Light mainLight = GetMainLight(i.shadowCoord);

                // 获取阴影衰减
                float shadow = mainLight.shadowAttenuation;

                float3 L = normalize(mainLight.direction); // 物体指向光源的向量
                float3 lightColor = mainLight.color;

                // 视角方向
                float3 V = normalize(GetCameraPositionWS() - i.positionWS);

                // ==== Lambert漫反射 ====
                // Lambert公式：最终颜色 = 主颜色 * 光颜色 * max(0, 单位法向 * 单位光方向);
                float NdotL = max(0, dot(N, L));
                float3 diffuse = _BaseColor.rgb * lightColor * NdotL * shadow; // 应用阴影到漫反射

                // ==== Blinn-Phong高光 ====
                // Blinn-Phone公式：高光强度 = pow(saturate(dot(N, H), _Shininess))
                // 最终高光强度 = 主颜色 * 光颜色 * 高光强度
                float3 H = normalize(L + V); // 半角向量
                float NdotH = max(0, dot(N, H));
                float spec = pow(NdotH, _Shininess);

                float3 specular = _SpecColor.rgb * lightColor * spec * shadow; // 应用阴影到高光

                // 多光源叠加（兼容 Forward 和 Forward+ 路径）
                // Forward+ 需要 InputData 来查找光源簇
                InputData inputData = (InputData)0;
                inputData.positionWS = i.positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);

                uint pixelLightCount = GetAdditionalLightsCount();
                LIGHT_LOOP_BEGIN(pixelLightCount)
                {
                    Light light = GetAdditionalLight(lightIndex, i.positionWS);

                    float3 L_add = normalize(light.direction);
                    float3 lightColor_add = light.color;
                    float atten = light.distanceAttenuation * light.shadowAttenuation;

                    float NdotL_add = max(0, dot(N, L_add));

                    // 计算叠加光的漫反射
                    float3 diffuse_add = _BaseColor.rgb * lightColor_add * NdotL_add * atten;
                    diffuse += diffuse_add;

                    // 计算高光叠加光
                    float3 H_add = normalize(L_add + V);
                    float NdotH_add = max(0, dot(N, H_add));
                    float spec_add = pow(NdotH_add, _Shininess);
                    float3 specular_add = _SpecColor.rgb * lightColor_add * spec_add * atten;
                    specular += specular_add;
                }
                LIGHT_LOOP_END

                // ==== 边缘光 ====
                // 边缘光公式：边缘光强度 = (1 - dot(N, V)) ^ _RimPower
                // 最终颜色 = 边缘光颜色 * 边缘光强度
                float rim = pow((1.0 - saturate(dot(N, V))), _RimPower);
                float3 rimColor = _RimColor.rgb * rim;

                // ==== 边缘光mask ====
                // 让边缘光只在暗面出现
                // 暗面权重 = 1 - max(0, dot(N, L))
                // 最终颜色 = rimColor * 暗面权重
                float darkMask = 1 - NdotL;
                rimColor = rimColor * darkMask * shadow; // 应用阴影到边缘光

                // 计算环境光
                // SH：是Spherical Harmonics（球谐函数）的缩写。可以把球面上的任意函数，用一组低频的基函数来近似表示。
                // SampleSH(N) 就是去查询：“在我的场景里，从法线 N 这个方向射来的环境光是什么颜色？
                float3 ambient = SampleSH(N);

                // 颜色合并
                float3 finalColor = diffuse + specular + ambient * _BaseColor.rgb + rimColor;

                return float4(finalColor, 1.0);
            }

            ENDHLSL // HLSL语法结束
        }
    }
}
