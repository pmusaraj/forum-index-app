# Jetson Orin Nano TRT 10.16 — INT8 DETR engine slower than FP16; NaNs when decoder is FP16

**URL:** <https://forums.developer.nvidia.com/t/jetson-orin-nano-trt-10-16-int8-detr-engine-slower-than-fp16-nans-when-decoder-is-fp16/387395>\
**Category:** Jetson Orin Nano\
**Tags:** tensorrt\
**Created:** [October 30, 2026, 5:40am UTC](https://forums.developer.nvidia.com/t/jetson-orin-nano-trt-10-16-int8-detr-engine-slower-than-fp16-nans-when-decoder-is-fp16/387395 "2026-10-30T05:40:54Z")\
**Posts on this page:** 3\
**Page:** 1

<div class="post-metadata">

**Author:** ![jagdish.k](https://developer.download.nvidia.com/images/forums/profile-default-devtalk-84.png) [@jagdish.k](https://forums.developer.nvidia.com/u/jagdish.k)\
**Post date:** [October 30, 2026, 5:40am UTC](https://forums.developer.nvidia.com/t/jetson-orin-nano-trt-10-16-int8-detr-engine-slower-than-fp16-nans-when-decoder-is-fp16/387395/1 "2026-10-30T05:40:54Z")

</div>

Hi,

I am quantizing transformer detectors with TensorRT 10.16.2.10 on a **Jetson Orin Nano** (JetPack / L4T with CUDA, no DLA on this SKU). Power mode is 15W (GPU ~612 MHz). Builder: optimization level 3, workspace ~256 MB, entropy calibration (`IInt8EntropyCalibrator2`), flags `INT8` + `FP16`, and usually `OBEY_PRECISION_CONSTRAINTS`. Latency is GPU time around `execute_async_v3` only.

**Model:** DEIMv2-N (HGNetv2 backbone + transformer decoder), ONNX exported for 640×640, COCO. Calibration 500 val2017 images; eval on the other 4,500.

**Problem 1 — INT8 slower than FP16**

A usable INT8 engine only works if I keep large parts of the decoder out of INT8:

- Backbone: INT8
- ~66 MatMuls: FP16
- LayerNorm / Softmax (and related Pow / Reduce): FP32
- Decoder + postprocessor: FP32

Measured mean latency on the same 4,500 images:

| **Precision** | **Mean ms** | **FPS** | **mAP 50–95** |
| --- | --- | --- | --- |
| FP32 | 21.95 | 45.6 | 0.351 |
| FP16 | 10.11 | 98.9 | 0.422 |
| INT8 (decoder FP32 as above) | **11.66** | 85.8 | 0.268 |

So this INT8 engine is **~15% slower than FP16** , and the engine size is almost the same as FP16 (~10.4 MB vs ~10.3 MB). Clocks were comparable (~608–609 MHz).

If I leave the decoder free / try to run more of it in INT8 or FP16 without those pins, LayerNorm (Pow/Reduce) and Softmax overflow or the build fails under `OBEY_PRECISION_CONSTRAINTS`.

**Problem 2 — NaNs when the whole decoder is FP16**

I built a second INT8+FP16 engine that kept the **entire decoder in FP16** (still pinning sensitive ops as needed). Engine size ~8.43 MB. At runtime every image produces **NaN scores and NaN boxes**. A pure FP16 engine (no INT8) is fine and does not NaN.

I also tried “fusion-blocked” variants (e.g. materializing only the Pow in the first decoder LayerNorm, or ~15 decoder tensors). Those stay finite and one of them is slightly faster than FP16 (~8.86 ms), but accuracy is still below FP16.

**Questions**

1. On Orin Nano, for DETR-style models, is **INT8 slower than FP16** expected when a large decoder must stay in FP32 for numerical stability? Is there a recommended precision mix (which ops stay FP16 vs FP32) that still beats FP16 latency without NaNs?
2. What is the usual root cause of **NaNs when INT8 feeds an FP16 decoder / LayerNorm** , while a standalone FP16 engine is stable? Is this known with fused LayerNorm (Pow + Reduce) under INT8+FP16 + `OBEY_PRECISION_CONSTRAINTS`?
3. Are there builder flags, calibrators, or layer-precision APIs NVIDIA recommends for transformer detectors on Jetson (e.g. stronger fallback without OBEY, or explicit unfusing of LayerNorm) so INT8 does not require keeping the whole decoder in FP32?

Happy to share ONNX layer names, builder log excerpts (`missing scale and zero-point`, kernel failures), and a short repro if that helps.

Thanks.

* * *

You can shorten the title if the forum has a length limit. If the thread is Jetson-specific, post under **Jetson / TensorRT** ; if it is general TensorRT, use the TensorRT forum and keep the Orin Nano line in the first paragraph.

---

<div class="post-metadata">

**Author:** ![MarkusHoHo](https://sea2.discourse-cdn.com/nvidia/user_avatar/forums.developer.nvidia.com/markushoho/32/233145_2.png) [@MarkusHoHo](https://forums.developer.nvidia.com/u/MarkusHoHo)\
**Post date:** [October 30, 2026, 6:01am UTC](https://forums.developer.nvidia.com/t/jetson-orin-nano-trt-10-16-int8-detr-engine-slower-than-fp16-nans-when-decoder-is-fp16/387395/2 "2026-10-30T06:01:43Z")

</div>

Hello @jagdish.k!

Based on the title and content of your topic, it looks like it may receive better visibility and feedback in a different category. We took the liberty of moving it for you.

If this was an incorrect assessment, please send me a direct message.

_Disclaimer: this moderation suggestion and message were generated with AI assistance._

---

<div class="post-metadata">

**Author:** ![AastaLLL](https://sea2.discourse-cdn.com/nvidia/user_avatar/forums.developer.nvidia.com/aastalll/32/14043_2.png) [@AastaLLL](https://forums.developer.nvidia.com/u/AastaLLL)\
**Post date:** [October 30, 2026, 1:09pm UTC](https://forums.developer.nvidia.com/t/jetson-orin-nano-trt-10-16-int8-detr-engine-slower-than-fp16-nans-when-decoder-is-fp16/387395/5 "2026-10-30T13:09:11Z")

</div>

HI,

Could you share with us a reduced model and the steps so we can check it further?  
Thanks.
