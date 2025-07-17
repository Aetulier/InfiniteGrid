Shader "Unlit/InfiniteHexagonalGrid"
{
    Properties
    {
        _GridColor("Grid Color", Color) = (0.5294118, 0.8078431, 0.9803922, 1)
        _RingColor("Ring Color", Color) = (0.5, 0.5, 0.5, 1)
        _GridScale("Grid Scale", Float) = 0.5
        [Toggle]_EnableRings("Enable Rings", Float) = 1
        _AnimationSpeed("Animation Speed", Float) = 1
        _FromOrigin("From Origin", Float) = 60.0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalRenderPipeline"
            "RenderType"="Transparent"
            "IgnoreProjector"="True"
            "Queue"="Transparent"
        }

        Pass
        {
            Name "InfiniteGrid"
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // Exposed properties
            CBUFFER_START(UnityPerMaterial)
                half4 _GridColor;
                half4 _RingColor;
                float _GridScale;
                float _EnableRings;
                float _AnimationSpeed;
                float _FromOrigin;
            CBUFFER_END

            struct Attributes
            {
                uint vertexID : SV_VertexID;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID, UNITY_RAW_FAR_CLIP_VALUE);
                return output;
            }

            #define TAU 6.2831853

            float2x2 makem2(float theta)
            {
                float c = cos(theta);
                float s = sin(theta);
                return float2x2(c, -s, s, c);
            }

            float fbm(float2 p)
            {
                float z = 2.0;
                float rz = 0.0;
                float2 bp = p;

                UNITY_UNROLL
                for (int i = 1; i < 6; i++)
                {
                    rz += abs(-0.5 * 2.0 / z);
                    z *= 2.0;
                    p *= 2.0;
                }
                return rz;
            }

            float dualfbm(float2 p)
            {
                // Get two rotated fbm calls and displace the domain
                float2 p2 = p * 0.7;
                float2 basis = float2(fbm(p2 - _Time.y * 0.1 * 1.6), fbm(p2 + _Time.y * 0.1 * 1.7));
                basis = (basis - 0.5) * 0.2;
                p += basis;

                // Coloring
                return fbm(mul(p, makem2(_Time.y * 0.1 * 0.2)));
            }

            // float hash21(float2 p)
            // {
            //     p = frac(p * float2(123.34, 456.21));
            //     p += dot(p, p + 45.32);
            //     return frac(p.x * p.y);
            // }
            //
            // float noise(in float2 p)
            // {
            //     float2 ip = floor(p);
            //     float2 fp = frac(p);
            //     fp = fp * fp * (3.0 - 2.0 * fp);
            //
            //     float a = hash21(ip);
            //     float b = hash21(ip + float2(1.0, 0.0));
            //     float c = hash21(ip + float2(0.0, 1.0));
            //     float d = hash21(ip + float2(1.0, 1.0));
            //
            //     return lerp(lerp(a, b, fp.x), lerp(c, d, fp.x), fp.y);
            // }

            float circ(float2 p)
            {
                float r = length(p);
                r = log(sqrt(r));
                float ring = abs(fmod(r * 4.0, TAU) - 3.14);

                // float noiseFactor = noise(p * 5.0) * 0.5;
                // ring += noiseFactor;

                return smoothstep(0.1, 0.5, ring) * 3.0 + 0.2;
            }

            void Hexagon_simplified(
                float2 UV,
                float Scale,
                float BaseAntiAliasWidth,
                out float Hexagon
            )
            {
                float2 dUVdx = ddx(UV * Scale);
                float2 dUVdy = ddy(UV * Scale);
                float pixelCoverage = max(length(dUVdx), length(dUVdy));
                float dynamicAAWidth = clamp(BaseAntiAliasWidth * pixelCoverage * 5, 0.001, 0.1);

                float2 p = UV * Scale;
                p.x *= 1.15470053838;

                float isTwo = frac(floor(p.x) / 2.0) * 2.0;
                p.y += isTwo * 0.5;

                p = frac(p) - 0.5;
                p = abs(p);

                float hexDist = max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0;
                Hexagon = 1.0 - smoothstep(0.0, dynamicAAWidth, abs(hexDist));
            }

            float computeViewZ(float3 pos)
            {
                float4 clip_space_pos = mul(UNITY_MATRIX_VP, float4(pos.xyz, 1.0));
                return clip_space_pos.w;
            }

            half4 frag(Varyings varyings) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(varyings);

                #if UNITY_REVERSED_Z
                float depth = SampleSceneDepth(varyings.positionCS.xy);
                #else
                float depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(varyings.positionCS.xy));
                #endif

                PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth,
                                                           UNITY_MATRIX_I_VP,
                                                           UNITY_MATRIX_V);
                float3 nearPositionWS = ComputeWorldSpacePosition(posInput.positionNDC, 1, UNITY_MATRIX_I_VP);
                float3 farPositionWS = ComputeWorldSpacePosition(posInput.positionNDC, 0, UNITY_MATRIX_I_VP);
                float t = -nearPositionWS.y / (farPositionWS.y - nearPositionWS.y);
                half ground = step(0, t);

                float3 positionWS = nearPositionWS + t * (farPositionWS - nearPositionWS);
                // float3 cameraPos = _WorldSpaceCameraPos;
                // float fromOrigin = abs(cameraPos.y);

                float viewZ = computeViewZ(positionWS);
                float2 uv = positionWS.xz;

                float fading = max(0.0, 1.0 - viewZ / _FromOrigin);

                float hexPattern;
                Hexagon_simplified(uv, _GridScale, 0.5, hexPattern);
                //half hexagonGrid = hexPattern * lerp(1, 0, min(1.0, fromOrigin / 50));

                float3 color = _GridColor.rgb;
                if (_EnableRings > 0.5)
                {
                    float2 p = uv * 2;
                    float rz = dualfbm(p);

                    // Rings effect
                    p /= exp(fmod(_Time.y * _AnimationSpeed, 3.14159));
                    float ringEffect = pow(abs(0.1 - circ(p)), 0.9);
                    rz *= ringEffect;

                    // Final color blending
                    color = _RingColor.rgb / rz;
                    color = pow(abs(color), half3(0.99, 0.99, 0.99));

                    float maxChannel = max(max(color.r, color.g), color.b);
                    float blendFactor = smoothstep(0.5, 1.5, maxChannel);

                    color = lerp(_GridColor.rgb, color, blendFactor);
                }

                return half4(color, ground * hexPattern * fading * 0.5f);
            }
            ENDHLSL
        }
    }
}