const resourceName = (): string => (window as any).GetParentResourceName?.() ?? 'hype-bodycam';

export const isNative = !!(window as any).invokeNative;

interface NuiResponse<T = unknown> {
    success: boolean;
    error?: string;
    data?: T;
};

export async function FetchNUI<T = unknown>(event: string, data?: unknown, mock?: T): Promise<NuiResponse<T>> {
    if (!isNative) {
        return { success: true, data: mock };
    }

    const response = await fetch(`https://${resourceName()}/${event}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(data ?? {}),
    });

    return response.json();
};

export const pad = (value: number, length = 2): string => String(Math.trunc(Math.abs(value))).padStart(length, '0');

/** Geçen süre (ms) -> "SS:DD:ss" veya "DD:ss" */
export const duration = (ms: number): string => {
    const total = Math.max(0, Math.floor(ms / 1000));
    const hours = Math.floor(total / 3600);
    const rest = `${pad(Math.floor((total % 3600) / 60))}:${pad(total % 60)}`;
    return hours ? `${pad(hours)}:${rest}` : rest;
};

/**
 * Gerçek Axon kayıt damgası: "2020-12-05 18:40:12 -0500"
 * @param utcOffset Saat dilimi (saat), false = yerel saat
 */
export const stamp = (date: Date, utcOffset: number | false = false): string => {
    const minutes = utcOffset === false ? -date.getTimezoneOffset() : Math.round(utcOffset * 60);
    const shifted = new Date(date.getTime() + minutes * 60_000);
    const iso = shifted.toISOString();
    const sign = minutes < 0 ? '-' : '+';
    const zone = `${sign}${pad(Math.floor(Math.abs(minutes) / 60))}${pad(Math.abs(minutes) % 60)}`;

    return `${iso.slice(0, 10)} ${iso.slice(11, 19)} ${zone}`;
};

const compassPoints = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

/** Derece -> pusula yönü (N, NE...) */
export const cardinal = (heading: number): string => compassPoints[Math.round((((heading % 360) + 360) % 360) / 45) % 8];
