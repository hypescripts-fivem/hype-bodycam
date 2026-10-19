import beepUrl from '../assets/beep.wav';

export type BeepKind = 'start' | 'stop' | 'reminder';

/**
 * beep.wav zaten aralıklı iki bip içerir (gerçek Axon sesi), her tür dosyayı bir kez çalar.
 * Açılış ve kapanış aynı; hatırlatma biraz daha kısa/ince
 */
const patterns: Record<BeepKind, { at: number; rate: number }[]> = {
    start: [{ at: 0, rate: 0.72 }],
    stop: [{ at: 0, rate: 0.72 }],
    reminder: [{ at: 0, rate: 1.08 }],
};

export function playBeep(kind: BeepKind, volume: number) {
    const pattern = patterns[kind] ?? patterns.reminder;

    for (const { at, rate } of pattern) {
        setTimeout(() => {
            const audio = new Audio(beepUrl);
            audio.volume = Math.max(0, Math.min(1, volume));
            audio.playbackRate = rate;
            audio.preservesPitch = false;
            audio.play().catch(() => undefined);
        }, at);
    }
}
