# KaskadOS Material 3 Comparison

Standalone Qt Quick application for comparing the current built-in KaskadOS
palette and controls with Kernora's default Material 3 palette and component
geometry.

The right-hand hybrid preview combines Kernora's green neutral surface ladder
with the KaskadOS accent family (`#9fe0b4` in dark mode), and the
right-hand slider follows the geometry of Kernora's `MSlider.qml`: a 40 px
active/inactive track, a 6 px gap, a narrow animated handle and the endpoint
dot. The implementation in this directory was written specifically for this
comparison tool; the values and behaviour were derived from Kernora's GPL
sources.

Source reference: <https://github.com/commywork9282-dotcom/Kernora-OS->

## Build and run

```sh
cmake -S tools/material3-comparison -B build/material3-comparison -G Ninja
cmake --build build/material3-comparison
./build/material3-comparison/kaskados-material3-comparison
```
