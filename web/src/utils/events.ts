import { useBodycamStore, type Hud, type Indicator, type OpenPayload, type StreamItem } from "../store/index";
import { isNative } from "./index";
import { playBeep, type BeepKind } from "./beep";

interface NuiMessage {
    action: string;
    payload: any;
}

export function messageEvent() {
    const handlers: Record<string, (payload: any) => void> = {
        'nui/open': (payload: OpenPayload) => useBodycamStore().Open(payload ?? {}),
        'nui/hide': () => useBodycamStore().Hide(),
        'nui/menu': (payload: { streams?: StreamItem[] }) => useBodycamStore().ShowMenu(payload?.streams),
        'nui/streams': (payload: { streams: StreamItem[] }) => useBodycamStore().SetStreams(payload.streams ?? []),
        'nui/connecting': (payload: StreamItem) => useBodycamStore().Connecting(payload),
        'nui/view': (payload: StreamItem) => useBodycamStore().View(payload),
        'nui/stream': (payload: StreamItem) => useBodycamStore().UpdateStream(payload),
        'nui/signal': (payload: { lost: boolean; ended?: boolean }) => useBodycamStore().SetSignal(!!payload?.lost, !!payload?.ended),
        'nui/hud': (payload: Hud) => useBodycamStore().SetHud(payload),
        'nui/indicator': (payload: Indicator) => useBodycamStore().SetIndicator(payload),
        'nui/beep': (payload: { kind: BeepKind; volume: number }) => playBeep(payload.kind, payload.volume),
    };

    window.addEventListener('message', ({ data }: MessageEvent<NuiMessage>) => {
        const handler = handlers[data?.action];

        if (handler) {
            handler(data.payload);
        } else {
            console.warn(`Unknown action received: ${data?.action}`);
        }
    });
};

export function keydownEvent() {
    window.addEventListener("keydown", ({ code }) => {
        const store = useBodycamStore();

        if (code === "Escape") {
            if (store.mode !== 'menu' || store.busy) return;
            if (store.search) store.search = '';
            else store.CloseUI();
            return;
        }

        if (!isNative && store.mode === 'view') browserPreview(code);
    });
};

/** Tarayıcıda (oyun dışı) arayüzü denemek için: L sinyal, K yayın sonu, Q/E yayın, TAB fleet kamera, B bip, Backspace liste */
function browserPreview(code: string) {
    const store = useBodycamStore();

    if (code === 'KeyL') return store.SetSignal(!store.signalLost);
    if (code === 'KeyK') return store.SetSignal(true, true);
    if (code === 'Backspace') return store.ShowMenu();

    if ((code === 'KeyQ' || code === 'KeyE') && store.stream) {
        const list = store.streams;
        const current = list.findIndex((stream) => stream.id === store.stream?.id);
        const next = list[(current + (code === 'KeyE' ? 1 : -1) + list.length) % list.length];
        store.Connecting(next);
        setTimeout(() => store.View(next), 600);
    }

    const hud = { ...store.hud };
    if (code === 'KeyA') hud.heading = (hud.heading + 355) % 360;
    if (code === 'KeyD') hud.heading = (hud.heading + 5) % 360;
    if (code === 'KeyW') hud.speed = (hud.speed ?? 0) + 8;
    if (code === 'KeyS') hud.speed = Math.max(0, (hud.speed ?? 0) - 8);
    if (code === 'KeyX') hud.lights = !hud.lights;
    if (code === 'KeyZ') hud.siren = !hud.siren;
    if (code === 'Tab' && store.stream?.type === 'dash') hud.cam = hud.cam === 2 ? 1 : 2;
    if (code === 'KeyB') playBeep('start', 0.5);
    store.SetHud(hud);
}
