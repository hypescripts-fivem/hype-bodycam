<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue';
import { useBodycamStore, type Filter } from '../store';
import { duration, pad } from '../utils';
import AppIcon from './AppIcon.vue';
import AxonMark from './AxonMark.vue';

const store = useBodycamStore();

const now = ref(Date.now());
let timer: ReturnType<typeof setInterval> | undefined;
onMounted(() => (timer = setInterval(() => (now.value = Date.now()), 1000)));
onBeforeUnmount(() => clearInterval(timer));

const time = computed(() => {
    const date = new Date(now.value);
    return `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
});

const filters = computed<{ id: Filter; label: string; icon: string }[]>(() => [
    { id: 'all', label: store.locale('ui.all'), icon: 'grid' },
    { id: 'body', label: store.locale('ui.body'), icon: 'body' },
    { id: 'dash', label: store.locale('ui.dash'), icon: 'dash' },
]);
</script>

<template>
    <div class="fixed inset-0 flex items-center justify-center bg-black/55">
        <div class="clip-panel flex h-[min(84vh,52rem)] w-[min(88vw,86rem)] flex-col border border-line bg-console/95 shadow-[0_2rem_5rem_rgba(0,0,0,0.6)]">
            <!-- Üst bar -->
            <header class="flex items-center gap-5 border-b border-line px-6 py-4">
                <div class="flex items-center gap-3">
                    <div class="flex h-11 w-11 items-center justify-center border border-axon/40 bg-axon/10 text-axon">
                        <AxonMark class="h-6 w-6" />
                    </div>
                    <div>
                        <div class="font-display text-[1.5rem] font-bold uppercase leading-none tracking-[0.14em] text-paper">{{ store.locale('ui.brand') }}</div>
                        <div class="mt-1 text-[0.68rem] tracking-[0.22em] text-paper/50">{{ store.locale('ui.subtitle').toLocaleUpperCase(store.ui.locale) }}</div>
                    </div>
                </div>

                <label class="ml-auto flex h-10 w-[22rem] items-center gap-2.5 border border-line bg-black/40 px-3 text-paper/50 focus-within:border-paper/40">
                    <AppIcon name="search" class="h-4 w-4 shrink-0" />
                    <input
                        v-model="store.search"
                        :placeholder="store.locale('ui.search')"
                        class="w-full bg-transparent text-[0.85rem] text-paper placeholder:text-paper/35 outline-none select-text"
                    />
                </label>

                <div class="text-right">
                    <div class="text-[1.25rem] font-bold leading-none tabular-nums text-paper">{{ time }}</div>
                    <div class="mt-1 flex items-center justify-end gap-1.5 text-[0.62rem] tracking-[0.15em] text-rec">
                        <span class="h-1.5 w-1.5 rounded-full bg-rec" />
                        {{ store.locale('ui.live_count', store.streams.length) }}
                    </div>
                </div>

                <button
                    class="flex h-10 w-10 cursor-pointer items-center justify-center border border-line text-paper/60 transition hover:border-alert/60 hover:bg-alert/10 hover:text-alert"
                    :title="store.locale('ui.close')"
                    @click="store.CloseUI()"
                >
                    <AppIcon name="close" class="h-5 w-5" />
                </button>
            </header>

            <div class="flex min-h-0 flex-1">
                <!-- Filtreler -->
                <nav class="w-[16rem] shrink-0 space-y-1 border-r border-line p-3">
                    <button
                        v-for="filter in filters" :key="filter.id"
                        class="flex w-full cursor-pointer items-center gap-3 border-l-2 px-3 py-2.5 text-left text-[0.82rem] transition"
                        :class="store.filter === filter.id
                            ? 'border-axon bg-paper/[0.07] text-paper'
                            : 'border-transparent text-paper/55 hover:bg-paper/[0.04] hover:text-paper/85'"
                        @click="store.filter = filter.id"
                    >
                        <AppIcon :name="filter.icon" class="h-[1.1rem] w-[1.1rem] shrink-0" />
                        <span class="flex-1 truncate font-semibold">{{ filter.label }}</span>
                        <span class="text-[0.7rem] tabular-nums text-paper/40">{{ store.countOf(filter.id) }}</span>
                    </button>
                </nav>

                <!-- Yayın ızgarası -->
                <section class="relative min-h-0 flex-1 overflow-y-auto p-4">
                    <div v-if="store.filtered.length" class="grid grid-cols-[repeat(auto-fill,minmax(19rem,1fr))] gap-3">
                        <button
                            v-for="stream in store.filtered" :key="stream.id"
                            class="clip-card group flex cursor-pointer flex-col border border-line bg-console-2 text-left transition hover:border-axon/50 disabled:cursor-not-allowed disabled:opacity-45"
                            :disabled="stream.self || store.busy"
                            @click="store.Connect(stream)"
                        >
                            <!-- Önizleme -->
                            <div class="static-thumb relative flex h-[7.5rem] w-full items-center justify-center overflow-hidden">
                                <AppIcon :name="stream.type" class="h-12 w-12 text-paper/15" />

                                <div class="absolute left-2.5 top-2 flex items-center gap-1.5 text-[0.6rem] font-bold tracking-[0.18em]">
                                    <span class="pulse-ring h-2 w-2 rounded-full bg-rec" />
                                    <span class="text-rec">{{ store.locale('ui.live') }}</span>
                                    <span class="text-paper/60 tabular-nums">{{ duration(now - (stream.startedAt ?? now)) }}</span>
                                </div>
                                <div class="absolute right-2.5 top-2 flex items-center gap-1 text-[0.55rem] font-bold tracking-[0.12em]">
                                    <span class="bg-axon px-1 py-px text-console">{{ stream.type === 'body' ? store.locale('ui.tag.bwc') : store.locale('ui.tag.fleet') }}</span>
                                    <span class="border border-paper/35 px-1 text-paper/75">{{ stream.type === 'body' ? store.locale('ui.tag.body3') : store.locale('ui.tag.fleet3') }}</span>
                                </div>
                                <div class="absolute bottom-2 left-2.5 flex items-center gap-1.5">
                                    <span class="font-axon text-[0.68rem] tracking-[0.08em] text-paper/70">{{ stream.serial }}</span>
                                    <span
                                        v-if="stream.trigger"
                                        class="border px-1 text-[0.52rem] font-bold tracking-[0.12em]"
                                        :class="stream.trigger === 'manual' || stream.trigger === 'entry' ? 'border-paper/30 text-paper/60' : 'border-rec/60 text-rec'"
                                    >{{ store.locale(`ui.trigger.${stream.trigger}`) }}</span>
                                </div>

                                <div v-if="stream.type === 'dash'" class="absolute bottom-2 right-2.5 flex items-center gap-1.5 text-[0.58rem] font-bold tracking-[0.14em]">
                                    <template v-if="stream.lights">
                                        <span class="lightbar-red h-1.5 w-3 bg-siren-red" />
                                        <span class="lightbar-blue h-1.5 w-3 bg-siren-blue" />
                                        <span class="text-paper/80">{{ store.locale('ui.lights_on') }}</span>
                                    </template>
                                    <span v-else class="text-paper/40">{{ store.locale('ui.lights_off') }}</span>
                                </div>

                                <div class="absolute inset-0 flex items-center justify-center bg-black/55 opacity-0 transition group-hover:opacity-100 group-disabled:hidden">
                                    <span class="flex items-center gap-2 border border-axon/60 bg-black/60 px-3 py-1.5 text-[0.72rem] font-bold tracking-[0.2em] text-axon">
                                        <AppIcon name="play" class="h-3.5 w-3.5" />
                                        {{ store.locale('ui.connect') }}
                                    </span>
                                </div>
                            </div>

                            <!-- Bilgiler -->
                            <div class="flex w-full items-start gap-3 border-t border-line px-3 py-2.5">
                                <div class="min-w-0 flex-1">
                                    <div class="flex items-center gap-2">
                                        <span class="truncate font-display text-[1.2rem] font-bold leading-tight text-paper">{{ stream.name }}</span>
                                        <span v-if="stream.self" class="border border-axon/50 px-1 text-[0.55rem] font-bold tracking-[0.15em] text-axon">{{ store.locale('ui.you') }}</span>
                                    </div>
                                    <div class="mt-0.5 truncate text-[0.68rem] tracking-[0.06em] text-paper/55">
                                        <template v-if="stream.type === 'dash'">{{ stream.vehicle }}</template>
                                        <template v-else>{{ [stream.job, stream.grade].filter(Boolean).join(' · ') }}</template>
                                    </div>
                                </div>
                                <div class="shrink-0 text-right">
                                    <div v-if="stream.type === 'dash' && stream.plate" class="border border-paper/30 bg-paper/90 px-1.5 text-[0.68rem] font-bold tracking-[0.1em] text-console">{{ stream.plate }}</div>
                                    <div v-if="stream.callsign" class="mt-1 text-[0.66rem] font-semibold tracking-[0.1em] text-axon/85">{{ stream.callsign }}</div>
                                </div>
                            </div>
                        </button>
                    </div>

                    <div v-else class="absolute inset-0 flex flex-col items-center justify-center text-center">
                        <AxonMark class="h-14 w-14 text-paper/10" />
                        <div class="mt-4 font-display text-[1.4rem] font-bold tracking-[0.15em] text-paper/60">{{ store.locale('ui.no_results') }}</div>
                        <div class="mt-1 max-w-[26rem] text-[0.72rem] text-paper/35">{{ store.locale('ui.no_results_sub') }}</div>
                    </div>

                    <Transition name="fade">
                        <div v-if="store.error" class="absolute bottom-4 left-1/2 -translate-x-1/2 border border-alert/50 bg-alert/15 px-4 py-2 text-[0.75rem] font-semibold text-alert">
                            {{ store.locale(`ui.error.${store.error}`) }}
                        </div>
                    </Transition>
                </section>
            </div>
        </div>
    </div>
</template>
