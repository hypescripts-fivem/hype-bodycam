<script setup lang="ts">
import { computed } from 'vue';
import { useBodycamStore, type Trigger } from '../store';
import AxonMark from './AxonMark.vue';

/** Bodycam açıkken memurun kendi ekranındaki Axon cihaz göstergesi (model, seri, kamera, tetikleyici) */
const store = useBodycamStore();

const positions: Record<string, string> = {
    'top-right': 'right-[1.6rem] top-[1.6rem]',
    'top-left': 'left-[1.6rem] top-[1.6rem]',
    'bottom-right': 'right-[1.6rem] bottom-[1.6rem]',
    'bottom-left': 'left-[1.6rem] bottom-[1.6rem]',
};

const position = computed(() => positions[store.indicator.position] ?? positions['top-right']);

const signal = (trigger?: Trigger) => trigger === 'sidearm' || trigger === 'vehicle' || trigger === 'lights';
const triggerLabel = (trigger?: Trigger) => (trigger ? store.locale(`ui.trigger.${trigger}`) : '');
</script>

<template>
    <div class="pointer-events-none fixed min-w-[16rem] border border-paper/15 bg-black/60 font-axon" :class="position">
        <!-- Bodycam -->
        <div class="flex items-start gap-2.5 px-2.5 py-2">
            <AxonMark class="mt-0.5 h-[1.9rem] w-[1.9rem] shrink-0 opacity-90" />
            <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2 text-[0.7rem] font-bold">
                    <span class="blink h-2 w-2 rounded-full bg-rec shadow-[0_0_0.4rem_var(--color-rec)]" />
                    <span class="tracking-[0.16em] text-rec">{{ store.locale('ui.rec') }}</span>
                    <span class="tracking-[0.06em] text-paper">{{ store.locale('ui.body_model') }}</span>
                </div>
                <div class="mt-0.5 text-[0.82rem] leading-tight tracking-[0.04em] text-white">{{ store.indicator.serial ?? '—' }}</div>
                <div class="mt-1 flex flex-wrap items-center gap-1 text-[0.52rem] font-bold tracking-[0.12em]">
                    <span class="bg-axon px-1 py-px text-console">{{ store.locale('ui.tag.bwc') }}</span>
                    <span class="border border-paper/35 px-1 text-paper/75">{{ store.locale('ui.cam.body') }}</span>
                    <span
                        v-if="store.indicator.trigger"
                        class="border px-1"
                        :class="signal(store.indicator.trigger) ? 'border-rec/60 text-rec' : 'border-paper/30 text-paper/60'"
                    >{{ triggerLabel(store.indicator.trigger) }}</span>
                </div>
            </div>
        </div>

        <!-- Fleet (araçtayken) -->
        <div class="border-t border-paper/10 px-2.5 py-1.5" :class="store.indicator.dash ? '' : 'opacity-35'">
            <div class="flex items-center gap-2 text-[0.62rem] font-bold">
                <span class="h-1.5 w-1.5 rounded-full" :class="store.indicator.dash ? 'blink bg-rec' : 'bg-paper/40'" />
                <span class="tracking-[0.06em] text-paper">{{ store.locale('ui.dash_model') }}</span>
                <span v-if="store.indicator.dash" class="ml-auto tracking-[0.04em] text-white">{{ store.indicator.dashSerial }}</span>
                <span v-else class="ml-auto tracking-[0.12em] text-paper/60">{{ store.locale('ui.indicator.standby') }}</span>
            </div>
            <div v-if="store.indicator.dash" class="mt-1 flex flex-wrap items-center gap-1 text-[0.52rem] font-bold tracking-[0.12em]">
                <span class="bg-axon px-1 py-px text-console">{{ store.locale('ui.tag.fleet') }}</span>
                <span class="border border-paper/35 px-1 text-paper/75">{{ store.locale('ui.cam.front') }}</span>
                <span
                    v-if="store.indicator.dashTrigger"
                    class="border px-1"
                    :class="signal(store.indicator.dashTrigger) ? 'border-rec/60 text-rec' : 'border-paper/30 text-paper/60'"
                >{{ triggerLabel(store.indicator.dashTrigger) }}</span>
            </div>
        </div>
    </div>
</template>
