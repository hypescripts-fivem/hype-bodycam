<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useBodycamStore } from '../store';
import { cardinal, duration, pad, stamp } from '../utils';
import AxonMark from './AxonMark.vue';
import NoiseCanvas from './NoiseCanvas.vue';

const store = useBodycamStore();

const now = ref(new Date());
let clockTimer: ReturnType<typeof setInterval> | undefined;
onMounted(() => (clockTimer = setInterval(() => (now.value = new Date()), 250)));
onBeforeUnmount(() => clearInterval(clockTimer));

const isDash = computed(() => store.stream?.type === 'dash');
const overlay = computed(() => store.connecting || store.signalLost);

const overlayText = computed(() => {
    if (store.ended) return { title: store.locale('ui.ended'), sub: store.locale('ui.ended_sub'), alert: true };
    if (store.signalLost) return { title: store.locale('ui.no_signal'), sub: store.locale('ui.no_signal_sub'), alert: true };
    return { title: store.locale('ui.connecting'), sub: store.locale('ui.connecting_sub'), alert: false };
});

const street = computed(() => [store.hud.street, store.hud.crossing].filter(Boolean).join(' / '));

/** Damganın 3. satırı: hangi kamera + kaydı ne başlattı */
const camTag = computed(() => {
    if (!isDash.value) return store.locale('ui.cam.body');
    return store.hud.cam === 2 ? store.locale('ui.cam.cabin') : store.locale('ui.cam.front');
});
const tagLine = computed(() => {
    const trigger = store.stream?.trigger ? store.locale(`ui.trigger.${store.stream.trigger}`) : '';
    return trigger ? `${camTag.value}  ${trigger}` : camTag.value;
});
const speedUnit = computed(() => store.locale(`ui.${store.ui.speedUnit}`));

const controls = computed(() => [
    { keys: ['Q', 'E'], label: store.locale('ui.controls.switch') },
    ...(isDash.value ? [{ keys: ['TAB'], label: store.locale('ui.controls.camera') }] : []),
    { keys: ['⌫'], label: store.locale('ui.controls.back') },
    { keys: ['ESC'], label: store.locale('ui.controls.exit') },
]);
</script>

<template>
    <div class="pointer-events-none fixed inset-0 overflow-hidden">
        <!-- Görüntü katmanları -->
        <div class="absolute inset-0 opacity-[0.05] mix-blend-screen"><NoiseCanvas :width="480" :height="270" /></div>
        <div class="scanlines absolute inset-0" />
        <div class="absolute inset-0" :class="isDash ? 'dash-tint' : 'fisheye'" />

        <!-- Sağ üst: gerçek Axon damgası (tarih saat dilim / model seri) + kamera ve tetikleyici tag'leri -->
        <div class="absolute right-[1.6vw] top-[2.4vw] flex items-start gap-[0.6vw]">
            <div class="axon-stamp text-[1.2vw] leading-[1.25]">
                <div>{{ stamp(now, store.ui.utcOffset) }}</div>
                <div>{{ isDash ? store.locale('ui.dash_model') : store.locale('ui.body_model') }} {{ store.stream?.serial }}</div>
                <div class="text-[0.82vw] text-white/90">{{ tagLine }}</div>
            </div>
            <AxonMark class="mt-[0.15vw] h-[3.3vw] w-[3.3vw] opacity-75" />
        </div>

        <!-- Sol üst: kayıt + kanal -->
        <div class="osd absolute left-[3rem] top-[2.6rem]">
            <div class="flex items-center gap-2.5 text-[0.95rem] font-bold tracking-[0.18em]">
                <AxonMark class="h-[1.15rem] w-[1.15rem] text-axon" />
                <span class="blink flex items-center gap-1.5 text-rec">
                    <span class="h-[0.65rem] w-[0.65rem] rounded-full bg-rec" />
                    {{ store.locale('ui.rec') }}
                </span>
                <span class="text-paper/70 tabular-nums">{{ duration(now.getTime() - (store.stream?.startedAt ?? now.getTime())) }}</span>
            </div>
            <div class="mt-1 text-[0.68rem] tracking-[0.22em] text-paper/70">
                CH {{ store.locale('ui.channel', pad(store.stream?.index ?? 0), pad(store.stream?.total ?? 0)) }}
            </div>
        </div>

        <!-- Dashcam: çakar/siren -->
        <div v-if="isDash" class="osd absolute left-1/2 top-[2.6rem] flex -translate-x-1/2 items-center gap-3 text-[0.8rem] font-bold tracking-[0.2em]">
            <template v-if="store.hud.lights">
                <span class="lightbar-red h-2.5 w-7 bg-siren-red shadow-[0_0_0.8rem_var(--color-siren-red)]" />
                <span>{{ store.locale('ui.lights_on') }}</span>
                <span v-if="store.hud.siren" class="border border-paper/70 px-1.5 text-[0.7rem]">{{ store.locale('ui.siren') }}</span>
                <span class="lightbar-blue h-2.5 w-7 bg-siren-blue shadow-[0_0_0.8rem_var(--color-siren-blue)]" />
            </template>
        </div>

        <!-- Sol alt: memur / araç -->
        <div class="osd absolute bottom-[2.8rem] left-[3rem] max-w-[34rem]">
            <div class="text-[0.62rem] font-bold tracking-[0.28em] text-axon">{{ isDash ? store.locale('ui.unit') : store.locale('ui.officer') }}</div>
            <div class="font-display text-[1.9rem] font-bold leading-none tracking-[0.03em]">
                {{ isDash ? (store.stream?.vehicle ?? '') : store.stream?.name }}
            </div>
            <div class="mt-1 flex flex-wrap items-center gap-x-3 text-[0.8rem] font-semibold tracking-[0.06em] text-paper/90">
                <span v-if="isDash && store.stream?.plate">{{ store.locale('ui.plate') }} {{ store.stream.plate }}</span>
                <span v-if="isDash">{{ store.stream?.name }}</span>
                <span v-if="store.stream?.callsign">{{ store.stream.callsign }}</span>
                <span v-if="!isDash">{{ [store.stream?.job, store.stream?.grade].filter(Boolean).join(' · ') }}</span>
                <span v-else-if="store.stream?.job">{{ store.stream.job }}</span>
            </div>
        </div>

        <!-- Sağ alt: konum (+ dashcam hız) -->
        <div class="osd absolute bottom-[2.8rem] right-[3rem] text-right">
            <div v-if="isDash && store.hud.speed != null" class="mb-1 font-axon text-[1.5rem] leading-none">
                {{ store.hud.speed }} <span class="text-[0.8rem]">{{ speedUnit }}</span>
            </div>
            <div class="text-[0.95rem] font-semibold tracking-[0.04em]">{{ street }}</div>
            <div class="text-[0.75rem] tracking-[0.12em] text-paper/80">{{ store.hud.zone?.toLocaleUpperCase(store.ui.locale) }}</div>
            <div class="mt-0.5 text-[0.7rem] tracking-[0.08em] text-paper/70 tabular-nums">
                {{ store.hud.lat.toFixed(1) }}, {{ store.hud.lon.toFixed(1) }}
                <span class="ml-2">{{ store.locale('ui.heading') }} {{ pad(store.hud.heading, 3) }}° {{ cardinal(store.hud.heading) }}</span>
            </div>
        </div>

        <!-- Alt orta: kontroller -->
        <div class="osd absolute bottom-[1.1rem] left-1/2 flex -translate-x-1/2 gap-4 text-[0.62rem]">
            <div v-for="control in controls" :key="control.label" class="flex items-center gap-1">
                <kbd
                    v-for="key in control.keys" :key="key"
                    class="min-w-[1.35rem] border border-paper/40 bg-black/45 px-1 py-px text-center font-mono text-[0.6rem] font-bold text-paper [text-shadow:none]"
                >{{ key }}</kbd>
                <span class="ml-0.5 tracking-[0.08em] text-paper/75">{{ control.label }}</span>
            </div>
        </div>

        <!-- Bağlanma / sinyal yok / yayın sonu -->
        <Transition name="fade">
            <div v-if="overlay" class="absolute inset-0">
                <div class="absolute inset-0 bg-[#111]"><NoiseCanvas :fps="30" /></div>
                <div class="scanlines absolute inset-0" />
                <div class="vignette absolute inset-0" />
                <div class="absolute left-1/2 top-1/2 -translate-x-1/2 -translate-y-1/2 text-center">
                    <div class="inline-block bg-black/80 px-6 py-3">
                        <div class="flex items-center justify-center gap-3">
                            <AxonMark class="h-7 w-7" :class="overlayText.alert ? 'text-alert' : 'text-axon'" />
                            <span class="font-display text-[2.4rem] font-bold leading-none tracking-[0.2em]" :class="overlayText.alert ? 'text-alert' : 'text-paper'">
                                {{ overlayText.title }}<span v-if="!overlayText.alert" class="blink">_</span>
                            </span>
                        </div>
                        <div class="mt-1.5 text-[0.75rem] tracking-[0.2em] text-paper/60">
                            {{ store.stream?.serial }} · {{ overlayText.sub }}
                        </div>
                    </div>
                </div>
            </div>
        </Transition>
    </div>
</template>
