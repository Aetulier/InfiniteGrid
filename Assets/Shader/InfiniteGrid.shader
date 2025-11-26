Shader "Unlit/InfiniteGrid"
{
    Properties
    {
        _GridColor("Grid Color", Color) = (0.5294118, 0.8078431, 0.9803922, 1)
        _RingColor("Ring Color", Color) = (0.5, 0.5, 0.5, 1)
        [Toggle]_EnableRings("Enable Rings", Float) = 1
        [KeywordEnum(Circle, Square)] _RingType("Ring Type", Float) = 0 // Dropdown to select ring shape
        _AnimationSpeed("Animation Speed", Float) = 1
        _FromOrigin("From Origin", Float) = 600.0
    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Transparent"
            "IgnoreProjector"="True"
            "Queue"="Transparent"
        }
        Pass
        {
            Name "InfiniteGrid"
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull off

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // Add compiler variants for different ring types
            #pragma shader_feature _RINGTYPE_CIRCLE _RINGTYPE_SQUARE

            #pragma vertex vert
            #pragma fragment frag

            CBUFFER_START(UnityPerMaterial)
                half4 _GridColor;
                half4 _RingColor;
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

            Varyings vert(Attributes input)
            {
                Varyings output;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID, UNITY_RAW_FAR_CLIP_VALUE);
                return output;
            }

            #define tau 6.2831853

            // Creates a 2x2 rotation matrix
            float2x2 makem2(float theta)
            {
                float c = cos(theta);
                float s = sin(theta);
                return float2x2(c, -s, s, c);
            }

            // Fractional Brownian motion function
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

            // Dual fractional Brownian motion
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

            // Square distance field function
            float rectangle(float2 p)
            {
                // Square distance field (returns distance to square edge)
                float2 q = abs(p); // Take absolute value to work in first quadrant
                float squareDist = max(q.x, q.y); // Square distance field

                // Logarithmic transformation (maintains original style)
                float r = log(sqrt(squareDist));
                float ring = abs(fmod(r * 4.0, tau) - 3.14); // Ring wave logic

                // Smooth transition
                float edge = smoothstep(0.1, 0.5, ring);
                return edge * 3.0 + 0.2;
            }

            // Circular distance field function
            float circ(float2 p)
            {
                float r = length(p);
                r = log(sqrt(r));
                float ring = abs(fmod(r * 4.0, tau) - 3.14);

                // Smooth transition (avoids hard edges)
                float edge = smoothstep(0.1, 0.5, ring);
                return edge * 3.0 + 0.2;
            }

            // Grid generation function
            half Grid(float2 uv)
            {
                float2 derivative = fwidth(uv);
                uv = frac(uv - 0.5); // Center alignment
                uv = abs(uv - 0.5);
                uv = uv / derivative;
                float min_value = min(uv.x, uv.y);
                half grid = 1.0 - min(min_value, 1.0);
                return grid;
            }

            // Calculates view space Z coordinate
            float computeViewZ(float3 pos)
            {
                float4 clip_space_pos = mul(UNITY_MATRIX_VP, float4(pos.xyz, 1.0));
                float viewZ = clip_space_pos.w; // According to projection matrix definition, positionCS.w = viewZ
                return viewZ;
            }

            half4 frag(Varyings varyings) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                // Depth sampling (handles reversed Z)
                #if UNITY_REVERSED_Z
                float depth = SampleSceneDepth(varyings.positionCS.xy);
                #else
                // Adjust Z to match NDC for OpenGL ([-1, 1])
                float depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(varyings.positionCS.xy));
                #endif

                // Calculate world position from depth
                PositionInputs posInput = GetPositionInput(varyings.positionCS.xy, _ScreenSize.zw, depth,
                                          UNITY_MATRIX_I_VP,
                                          UNITY_MATRIX_V);
                float3 nearPositionWS = ComputeWorldSpacePosition(posInput.positionNDC, 1, UNITY_MATRIX_I_VP);
                float3 farPositionWS = ComputeWorldSpacePosition(posInput.positionNDC, 0, UNITY_MATRIX_I_VP);

                // Calculate ground intersection
                float t = -nearPositionWS.y / (farPositionWS.y - nearPositionWS.y);
                half ground = step(0, t);

                float3 positionWS = nearPositionWS + t * (farPositionWS - nearPositionWS);
                float3 cameraPos = _WorldSpaceCameraPos;
                float fromOrigin = abs(cameraPos.y);

                // Calculate view space Z and UV coordinates
                float viewZ = computeViewZ(positionWS);
                float2 uv = positionWS.xz;

                // Calculate grid with distance-based fading
                float fading = max(0.0, 1.0 - viewZ / _FromOrigin);
                half smallGrid = Grid(uv * 0.5) * lerp(1, 0, min(1.0, fromOrigin / 100));
                half middleGrid = Grid(uv * 0.1) * lerp(1, 0, min(1.0, fromOrigin / 300));
                half largeGrid = Grid(uv * 0.01) * lerp(1, 0, min(1.0, fromOrigin / 800));

                // Combine grid levels
                half grid = smallGrid + middleGrid + largeGrid;
                float3 color = _GridColor.rgb;

                // Ring effect processing (only if enabled)
                if (_EnableRings > 0.5)
                {
                    float2 p = uv;
                    p *= 2;
                    float rz = dualfbm(p);

                    // Apply ring effect based on selected type
                    p /= exp(fmod(_Time.y * _AnimationSpeed, 3.14159));
                    float ringEffect;

                    #if defined(_RINGTYPE_CIRCLE)
                    ringEffect = pow(abs(0.1 - circ(p)), 0.9); // Circular rings
                    #else
                        ringEffect = pow(abs(0.1 - rectangle(p)), 0.9); // Square rings
                    #endif

                    rz *= ringEffect;

                    // Final color calculation with blending
                    color = (_RingColor / rz).rgb;
                    color = pow(abs(color), half3(0.99, 0.99, 0.99));

                    float maxChannel = max(max(color.r, color.g), color.b);
                    float blendFactor = smoothstep(0.5, 1.5, maxChannel);

                    color = lerp(_GridColor.rgb, color, blendFactor);
                }

                // Return final color with transparency
                return half4(color, ground * grid * fading * 0.5);
            }
            ENDHLSL
        }
    }
}