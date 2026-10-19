<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue';

/** Düşük çözünürlüklü, canlı kamera parazitı (gri tonlu rastgele gürültü) */
const props = withDefaults(defineProps<{ fps?: number; width?: number; height?: number }>(), {
    fps: 24,
    width: 320,
    height: 180,
});

const canvas = ref<HTMLCanvasElement | null>(null);
let frame = 0;
let last = 0;

onMounted(() => {
    const ctx = canvas.value?.getContext('2d');
    if (!ctx) return;

    const image = ctx.createImageData(props.width, props.height);
    const pixels = new Uint32Array(image.data.buffer);
    const interval = 1000 / props.fps;

    const draw = (time: number) => {
        frame = requestAnimationFrame(draw);
        if (time - last < interval) return;
        last = time;

        for (let i = 0; i < pixels.length; i++) {
            const v = (Math.random() * 255) | 0;
            pixels[i] = 0xff000000 | (v << 16) | (v << 8) | v;
        }
        ctx.putImageData(image, 0, 0);
    };

    frame = requestAnimationFrame(draw);
});

onBeforeUnmount(() => cancelAnimationFrame(frame));
</script>

<template>
    <canvas ref="canvas" :width="width" :height="height" class="h-full w-full" />
</template>
