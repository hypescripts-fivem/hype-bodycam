<script setup lang="ts">
import { computed } from 'vue';

const props = defineProps<{ name: string }>();

const icons: Record<string, string[]> = {
    body: ['M8 3h8a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z', 'M12 11a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z', 'M9 16h6', 'M9 18.5h6'],
    dash: ['M5 17h14', 'M3 13l2-6a2 2 0 0 1 1.9-1.4h10.2A2 2 0 0 1 19 7l2 6v4a1 1 0 0 1-1 1h-1.5', 'M5.5 18H4a1 1 0 0 1-1-1v-4h18', 'M7 18a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z', 'M17 18a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3z'],
    grid: ['M3 3h7v7H3z', 'M14 3h7v7h-7z', 'M14 14h7v7h-7z', 'M3 14h7v7H3z'],
    search: ['M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16z', 'M21 21l-4.3-4.3'],
    close: ['M18 6 6 18', 'M6 6l12 12'],
    user: ['M12 12a5 5 0 1 0 0-10 5 5 0 0 0 0 10z', 'M3 22a9 9 0 0 1 18 0'],
    signal: ['M2 20h.01', 'M7 20v-4', 'M12 20v-8', 'M17 20V8', 'M22 4v16'],
    play: ['M7 4v16l13-8z'],
    pin: ['M12 21s-7-6.2-7-12a7 7 0 0 1 14 0c0 5.8-7 12-7 12z', 'M12 11.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z'],
};

const paths = computed(() => icons[props.name] ?? icons.body);
</script>

<template>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path v-for="(d, i) in paths" :key="i" :d="d" />
    </svg>
</template>
