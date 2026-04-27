Shader "Custom/URP/URPBasic"
{
    Properties
    {
        _BaseColor ("主颜色", Color) = (1, 1, 1, 1)
        _SpecColor ("高光颜色", Color) = (1, 1, 1, 1)
        _Shininess ("高光指数", Range(1, 128)) = 32
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
            };

            // 常量缓冲区 与Property一一对应
            // UnityPerMaterial 是这个常量缓冲区的名字
            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _SpecColor;
                float _Shininess;
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

                return o;
            }

            float4 frag (Varyings i) : SV_Target // 系统值语义 这个函数的返回值 就是渲染目标的颜色
            {
                // 归一化
                float3 N = normalize(i.normalWS);

                // 获取主光
                Light mainLight = GetMainLight();

                float3 L = normalize(mainLight.direction); // 物体指向光源的向量
                float3 lightColor = mainLight.color;

                // 视角方向
                float3 V = normalize(GetCameraPositionWS() - i.positionWS);

                // ==== Lambert漫反射 ====
                // Lambert公式：最终颜色 = 主颜色 * 光颜色 * max(0, 单位法向 * 单位光方向);
                float NdotL = max(0, dot(N, L));
                float3 diffuse = _BaseColor.rgb * lightColor * NdotL;

                // ==== Blinn-Phong高光 ====
                // Blinn-Phone公式：高光强度 = pow(saturate(dot(N, H), _Shininess))
                // 最终高光强度 = 主颜色 * 光颜色 * 高光强度
                float3 H = normalize(L + V); // 半角向量
                float NdotH = max(0, dot(N, H));
                float spec = pow(NdotH, _Shininess);

                float3 specular = _SpecColor.rgb * lightColor * spec;

                // 计算环境光
                // SH：是Spherical Harmonics（球谐函数）的缩写。可以把球面上的任意函数，用一组低频的基函数来近似表示。
                // SampleSH(N) 就是去查询：“在我的场景里，从法线 N 这个方向射来的环境光是什么颜色？
                float3 ambient = SampleSH(N);

                // 颜色合并
                float3 finalColor = diffuse + specular + ambient * _BaseColor.rgb;

                return float4(finalColor, 1.0);
            }

            ENDHLSL // HLSL语法结束
        }
    }
}
