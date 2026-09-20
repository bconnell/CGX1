# Public Sources

[Documentation index](README.md) · [Reference comparison](REFERENCE_COMPARISON.md) · [Prototype procurement](PROTOTYPE_PROCUREMENT.md)

Accessed September 20, 2026 unless otherwise noted.

## GPU and memory references

1. **NVIDIA RTX PRO 6000 Blackwell Workstation Edition product datasheet.** Product figure: 125 TFLOPS FP32, 380 RT TFLOPS, 96 GB GDDR7 ECC, 1.792 TB/s memory bandwidth, four NVENC, four NVDEC, 600 W, 5.4 inch × 12 inch dual slot.  
   https://www.nvidia.com/content/dam/en-zz/Solutions/data-center/rtx-pro-6000-blackwell-workstation-edition/workstation-blackwell-rtx-pro-6000-workstation-edition-nvidia-us-3519208-web.pdf

2. **NVIDIA RTX PRO 6000 Blackwell product family.** Current product family and form factor reference.  
   https://www.nvidia.com/en-us/products/workstations/professional-desktop-gpus/rtx-pro-6000-family/

3. **NVIDIA RTX Blackwell PRO GPU Architecture.** Architecture appendix lists 126.0 TFLOPS FP32 and 381.8 RT TFLOPS for the RTX PRO 6000 Blackwell Workstation Edition. This differs slightly from the product datasheet; [Reference Comparison](REFERENCE_COMPARISON.md) uses the product datasheet values.  
   https://www.nvidia.com/content/dam/en-zz/Solutions/design-visualization/quadro-product-literature/pdf/NVIDIA-RTX-Blackwell-PRO-GPU-Architecture-v1_1.pdf

4. **NVIDIA GeForce RTX 5090 product specifications.** 21,760 CUDA cores, 32 GB GDDR7, 575 W total graphics power.  
   https://www.nvidia.com/en-us/geforce/graphics-cards/50-series/rtx-5090/

5. **NVIDIA RTX Blackwell GPU Architecture.** Architecture appendix publishes approximately 104.8 TFLOPS peak FP32 for RTX 5090.  
   https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf

6. **Samsung HBM4 commercial shipment information.** Up to 3.3 TB/s per stack, 24 to 36 GB using 12 layers, and up to 48 GB with 16 layer stacking.  
   https://news.samsungsemiconductor.com/global/samsung-ships-industry-first-commercial-hbm4-with-ultimate-performance-for-ai-computing/

7. **Samsung HBM product information.**  
   https://semiconductor.samsung.com/dram/hbm/

8. **SK hynix HBM4 technology demonstrations.** Includes 48 GB 16 layer development references.  
   https://news.skhynix.com/en/sk-hynix-showcases-next-generation-ai-memory-innovations-at-ces-2026/

9. **Micron HBM4 product information.**  
   https://www.micron.com/products/memory/hbm/hbm4

## Process and PCIe references

10. **TSMC 2026 annual meeting material.** N2 entered high volume manufacturing in Q4 2025; N2P and A16 volume production are scheduled for the second half of 2026.  
    https://investor.tsmc.com/sites/ir/shareholders-meeting/2026-06-04/2026AGM_Agenda_wmn.pdf

11. **TSMC A16.** TSMC states A16 is production ready in 2H26 and targets HPC with backside power delivery.  
    https://www.tsmc.com/english/dedicatedFoundry/technology/logic/l_A16

12. **PCI SIG PCI Express 6.0.** PCI SIG states PCIe 6.0 maintains backward compatibility with previous PCIe generations.  
    https://pcisig.com/pci-express-6.0-specification

13. **PCI Express Card Electromechanical specification overview.** Current approved CEM revision information.  
    https://pcisig.com/specification-overview/pci-express-cem

## Prototype component references

14. **Corsair XR5 240 radiator.** Published dimensions: 280 × 120 × 30 mm. Price snapshot: $74.99.  
    https://www.corsair.com/us/en/p/custom-liquid-cooling/cx-9030002-ww/hydro-x-series-xr5-240mm-water-cooling-radiator-cx-9030002-ww

15. **Alphacool ES Reservoir DDCzero 1U with Pump, part 14571.** Published dimensions: 112 × 57 × 41.95 mm; up to 220 L/h maximum flow and 1.4 m head.  
    https://shop.alphacool.com/detail/index/sArticle/22592

16. **Titan Rig US listing for Alphacool 14571.** Price snapshot: $199.99.  
    https://www.titanrig.com/alphacool-es-reservoir-ddczero-1u-with-pump.html

17. **Same Sky CFM-5010B-170-361-22.** Active 12 V, 50 × 50 × 10 mm, PWM/tachometer fan reference.  
    https://www.sameskydevices.com/product/thermal-management/dc-fans/axial-fans/cfm-5010b-170-361-22

18. **Mean Well LRS-600N2-48.** 48 V, 600 W, 12.5 A external supply reference.  
    https://www.digikey.com/en/products/detail/mean-well-usa-inc/LRS-600N2-48/21531502

19. **AMD Alveo U50 data sheet.** Production U50: 75 W, 8 GB HBM2, Gen3 ×16 / Gen4 ×8, up to 316 GB/s measured peak HBM2 bandwidth with the documented qualification.  
    https://docs.amd.com/r/en-US/ds965-u50/Product-Details

20. **AMD Alveo U50 product page.** Reference procurement source.  
    https://www.amd.com/en/products/accelerators/alveo/u50/a-u50-p00g-pq-g.html

21. **JLCPCB assembly pricing reference.** Obtain a new quote from final manufacturing files before ordering.  
    https://jlcpcb.com/help/article/pcb-assembly-price

## Architecture standards references

22. **UCIe Consortium UCIe 3.0 specification overview.** UCIe 3.0 adds 48 GT/s and 64 GT/s data rates, priority sideband packets, fast throttle/emergency shutdown and expanded management features.  
    https://www.uciexpress.org/specifications

23. **Khronos Vulkan Roadmap 2026.** Defines the 2026 roadmap milestone for newer mid/high-end devices and lists features including fragment shading rate, shader clock, compute shader derivatives, cooperative matrix and presentation extensions.  
    https://github.khronos.org/Vulkan-Site/spec/latest/appendices/roadmap.html

24. **PCI-SIG Process Address Space ID (PASID).** Defines the 20-bit PASID field and process-address-space identification model.  
    https://pcisig.com/PCIExpress/ECN/Base/ProcessAddressSpaceID

25. **PCI-SIG PASID Translation.** Defines PASID use with address translation services and page request behavior.  
    https://pcisig.com/PCIExpress/ECN/Base/PASIDTranslation

## Repository tooling reference

26. **actions/checkout v7.0.1.** Repository workflow is pinned to commit `3d3c42e5aac5ba805825da76410c181273ba90b1`.  
    https://github.com/actions/checkout/releases/tag/v7.0.1

Retail listings are sourcing references, not endorsements or guarantees of future availability.
