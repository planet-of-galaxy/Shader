Shader "Custom/Basic"
{
    Properties
    {
        _MainColor ("主颜色", Color) = (1, 1, 1, 1)
        _MainTex ("主纹理", 2D) = "white" {}
    }
    
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 200
        
        Pass
        {
            Tags { "LightMode"="ForwardBase" }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            
            // 材质属性
            fixed4 _MainColor;
            sampler2D _MainTex;
            float4 _MainTex_ST;  // 纹理的缩放和偏移
            
            // 顶点输入结构
            struct appdata
            {
                float4 vertex : POSITION;   // 顶点位置
                float2 uv : TEXCOORD0;      // 纹理坐标
                float3 normal : NORMAL;     // 顶点法线
            };
            
            // 顶点输出结构（传递给片元着色器的数据）
            struct v2f
            {
                float4 pos : SV_POSITION;           // 裁剪空间位置
                float2 uv : TEXCOORD0;              // 纹理坐标
                float3 worldNormal : TEXCOORD1;     // 世界空间法线
            };
            
            // 顶点着色器
            v2f vert(appdata v)
            {
                v2f o;
                
                // 1. 将顶点从模型空间转换到裁剪空间（必须）
                o.pos = UnityObjectToClipPos(v.vertex);
                
                // 2. 计算纹理坐标（支持平铺偏移）
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                
                // 3. 将法线从模型空间转换到世界空间
                // UnityObjectToWorldNormal 函数会自动处理法线变换（包括缩放修正）
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                
                return o;
            }
            
            // 片元着色器
            fixed4 frag(v2f i) : SV_Target
            {
                // ========== 漫反射光照计算 ==========
                // 公式：漫反射颜色 = 光源颜色 × 材质颜色 × max(0, dot(法线, 光源方向))
                
                // 1. 获取纹理颜色和主颜色
                fixed4 albedo = tex2D(_MainTex, i.uv) * _MainColor;
                
                // 2. 获取光源方向（归一化）
                // 注意：_WorldSpaceLightPos0 对于平行光表示方向，对于点光源表示位置
                float3 lightDir = normalize(_WorldSpaceLightPos0.xyz);
                
                // 3. 获取法线（归一化）
                float3 normal = normalize(i.worldNormal);
                
                // 4. 计算漫反射强度（Lambert公式）
                float diffuseStrength = max(0, dot(normal, lightDir));
                
                // 5. 获取光源颜色和强度（_LightColor0 来自 Lighting.cginc）
                fixed4 lightColor = _LightColor0;
                
                // 6. 计算最终漫反射颜色
                fixed4 diffuse = albedo * lightColor * diffuseStrength;
                
                // 7. 添加环境光（避免完全黑暗的背面）
                fixed4 ambient = albedo * UNITY_LIGHTMODEL_AMBIENT;
                
                // 8. 合并结果
                fixed4 finalColor = diffuse + ambient;
                
                return finalColor;
            }
            ENDCG
        }
    }
    
    FallBack "Diffuse"
}