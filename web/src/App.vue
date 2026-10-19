<script setup lang="ts">
import { onMounted } from 'vue';
import Indicator from './components/Indicator.vue';
import StreamMenu from './components/StreamMenu.vue';
import StreamView from './components/StreamView.vue';
import { useBodycamStore } from './store';
import { isNative } from './utils';
import { keydownEvent, messageEvent } from './utils/events';

const store = useBodycamStore();

onMounted(() => {
    messageEvent();
    keydownEvent();

    // Tarayıcı önizlemesi: ?view=<yayın id> doğrudan izleme ekranını açar
    const id = !isNative && new URLSearchParams(location.search).get('view');
    const stream = id && store.streams.find((item) => item.id === id);
    if (stream) store.View(stream);
});
</script>

<template>
    <div v-if="!isNative" class="preview-bg fixed inset-0" />
    <Transition name="indicator">
        <Indicator v-if="store.indicator.body && store.mode !== 'view'" />
    </Transition>
    <Transition name="menu">
        <StreamMenu v-if="store.mode === 'menu'" />
    </Transition>
    <StreamView v-if="store.mode === 'view'" />
</template>
