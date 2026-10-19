import { defineStore } from 'pinia';
import { FetchNUI, isNative } from '../utils';
import previewLocale from '../../../locales/tr.json';

export type Mode = 'hidden' | 'menu' | 'view';
export type StreamType = 'body' | 'dash';
export type Filter = 'all' | StreamType;
export type IndicatorPosition = 'top-right' | 'top-left' | 'bottom-right' | 'bottom-left';

export type Trigger = 'manual' | 'sidearm' | 'vehicle' | 'entry' | 'lights';

export interface UIConfig {
    /** Kayıt damgasının saat dilimi (saat), false = yerel saat */
    utcOffset: number | false;
    locale: string;
    speedUnit: 'kmh' | 'mph';
    indicator: boolean;
    indicatorPosition: IndicatorPosition;
}

export interface StreamItem {
    id: string;
    type: StreamType;
    name: string;
    callsign?: string;
    job?: string;
    grade?: string;
    /** Cihaz seri numarası (X + 8 hane) */
    serial: string;
    /** Kaydı başlatan olay */
    trigger?: Trigger;
    plate?: string;
    vehicle?: string;
    lights?: boolean;
    /** Yayının başlamasından bu yana geçen süre (sn) */
    elapsed: number;
    /** Kendi yaka kameran */
    self: boolean;
    index: number;
    total: number;
    /** elapsed'den hesaplanan başlama zamanı (Date.now tabanlı) */
    startedAt?: number;
}

export interface Hud {
    heading: number;
    street?: string;
    crossing?: string;
    zone?: string;
    lat: number;
    lon: number;
    speed?: number;
    lights?: boolean;
    siren?: boolean;
    /** Fleet: 1 = ön, 2 = kabin */
    cam?: number;
}

export interface Indicator {
    body: boolean;
    dash: boolean;
    /** Bodycam cihaz seri numarası */
    serial?: string;
    trigger?: Trigger;
    /** Bindiği aracın Fleet seri numarası */
    dashSerial?: string;
    dashTrigger?: Trigger;
    position: IndicatorPosition;
}

export interface OpenPayload {
    locales?: Record<string, string>;
    ui?: UIConfig;
    debug?: boolean;
    streams?: StreamItem[];
}

const mockStreams = (): StreamItem[] => {
    const list: Omit<StreamItem, 'index' | 'total'>[] = [
        { id: 'b1', type: 'body', name: 'Daniel Brooks', callsign: '1-ADAM-12', job: 'LSPD', grade: 'Sergeant', serial: 'X60312274', trigger: 'manual', elapsed: 1843, self: false },
        { id: 'b2', type: 'body', name: 'Maria Lopez', callsign: '1-ADAM-14', job: 'LSPD', grade: 'Officer', serial: 'X60318190', trigger: 'sidearm', elapsed: 422, self: false },
        { id: 'b3', type: 'body', name: 'Ethan Walker', callsign: '3-LINCOLN-2', job: 'BCSO', grade: 'Deputy', serial: 'X60310457', trigger: 'manual', elapsed: 96, self: true },
        { id: 'b4', type: 'body', name: 'Chloe Reed', job: 'BCSO', grade: 'Deputy', serial: 'X60317733', trigger: 'vehicle', elapsed: 3721, self: false },
        { id: 'd87', type: 'dash', name: 'Daniel Brooks', callsign: '1-ADAM-12', job: 'LSPD', serial: 'X73302961', trigger: 'lights', plate: 'LSPD 012', vehicle: 'Police Cruiser', lights: true, elapsed: 1610, self: false },
        { id: 'd133', type: 'dash', name: 'Chloe Reed', job: 'BCSO', serial: 'X73308412', trigger: 'entry', plate: 'BCSO 207', vehicle: 'Sheriff SUV', lights: false, elapsed: 254, self: false },
    ];

    return list.map((stream, i) => ({ ...stream, index: i + 1, total: list.length }));
};

/** ox_lib'in lib.getLocales() çıktısı gibi iç içe anahtarları "a.b.c" biçimine düzleştirir */
const flatten = (source: Record<string, unknown>, prefix = '', out: Record<string, string> = {}): Record<string, string> => {
    for (const [key, value] of Object.entries(source)) {
        const path = prefix ? `${prefix}.${key}` : key;
        if (value && typeof value === 'object') flatten(value as Record<string, unknown>, path, out);
        else out[path] = String(value);
    }
    return out;
};

const withStart = <T extends StreamItem>(stream: T): T => ({ ...stream, startedAt: Date.now() - stream.elapsed * 1000 });

const defaultHud = (): Hud => ({ heading: 214, street: 'Vespucci Blvd', crossing: 'Sinner St', zone: 'Mission Row', lat: -1021.4, lon: 412.8, speed: 64, lights: true, siren: false, cam: 1 });

let errorTimer: ReturnType<typeof setTimeout> | undefined;

export const useBodycamStore = defineStore('Bodycam', {
    state: () => ({
        mode: (isNative ? 'hidden' : 'menu') as Mode,
        locales: (isNative ? {} : flatten(previewLocale)) as Record<string, string>,
        ui: { utcOffset: false, locale: 'tr-TR', speedUnit: 'kmh', indicator: true, indicatorPosition: 'top-right' } as UIConfig,
        streams: mockStreams().map(withStart),
        filter: 'all' as Filter,
        search: '',
        busy: false,
        error: null as string | null,
        stream: null as StreamItem | null,
        connecting: false,
        signalLost: false,
        ended: false,
        hud: defaultHud(),
        indicator: {
            body: !isNative,
            dash: !isNative,
            serial: 'X60312274',
            trigger: 'sidearm',
            dashSerial: 'X73302961',
            dashTrigger: 'lights',
            position: 'top-right',
        } as Indicator,
    }),
    getters: {
        locale: (state) => (key: string, ...args: (string | number)[]): string => {
            const text = state.locales[key] ?? key;
            if (!args.length) return text;

            let index = 0;
            return text.replace(/%[sd]/g, () => String(args[index++] ?? ''));
        },
        filtered(state): StreamItem[] {
            const query = state.search.trim().toLocaleLowerCase(state.ui.locale);
            return state.streams.filter((stream) => {
                if (state.filter !== 'all' && stream.type !== state.filter) return false;
                if (!query) return true;
                return [stream.name, stream.callsign, stream.job, stream.serial, stream.plate, stream.vehicle]
                    .filter(Boolean).join(' ').toLocaleLowerCase(state.ui.locale).includes(query);
            });
        },
        countOf: (state) => (filter: Filter): number =>
            filter === 'all' ? state.streams.length : state.streams.filter((stream) => stream.type === filter).length,
    },
    actions: {
        Open(payload: OpenPayload) {
            if (payload.locales) this.locales = payload.locales;
            if (payload.ui) this.ui = payload.ui;
            if (payload.streams) this.streams = payload.streams.map(withStart);

            this.filter = 'all';
            this.search = '';
            this.ShowMenu();
        },
        ShowMenu(streams?: StreamItem[]) {
            if (streams) this.streams = streams.map(withStart);
            this.mode = 'menu';
            this.stream = null;
            this.connecting = false;
            this.signalLost = false;
            this.ended = false;
            this.busy = false;
            this.error = null;
        },
        SetStreams(streams: StreamItem[]) {
            this.streams = streams.map(withStart);
        },
        Hide() {
            this.mode = 'hidden';
            this.stream = null;
            this.busy = false;
            this.error = null;
        },
        CloseUI() {
            if (this.mode === 'hidden') return;
            this.Hide();
            FetchNUI('nui/close');
        },
        Connecting(stream: StreamItem) {
            this.mode = 'view';
            this.stream = withStart(stream);
            this.connecting = true;
            this.signalLost = false;
            this.ended = false;
        },
        View(stream: StreamItem) {
            this.mode = 'view';
            this.stream = withStart(stream);
            this.connecting = false;
            this.busy = false;
        },
        /** Sahip/ışık değişimi; başlama zamanını koru ki süre sayacı zıplamasın */
        UpdateStream(stream: StreamItem) {
            if (this.stream?.id !== stream.id) return;
            this.stream = { ...withStart(stream), startedAt: this.stream.startedAt };
        },
        SetSignal(lost: boolean, ended = false) {
            this.signalLost = lost;
            this.ended = ended;
        },
        SetHud(hud: Hud) {
            this.hud = hud;
        },
        SetIndicator({ locales, ...indicator }: Indicator & { locales?: Record<string, string> }) {
            if (locales) this.locales = locales;
            this.indicator = indicator;
        },
        SetError(error: string) {
            this.error = error;
            clearTimeout(errorTimer);
            errorTimer = setTimeout(() => (this.error = null), 3500);
        },
        async Connect(stream: StreamItem) {
            if (this.busy || stream.self) return;

            this.busy = true;
            this.error = null;

            if (!isNative) {
                this.Connecting(stream);
                setTimeout(() => this.View(stream), 900);
                return;
            }

            const response = await FetchNUI('nui/view', { id: stream.id });
            this.busy = false;

            if (!response.success && response.error !== 'cancelled') {
                this.SetError(response.error ?? 'invalid');
            }
        },
    },
});
