/** 1x1 PNG with valid magic bytes. */
export const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  'base64',
);

/** Minimal JPEG header (enough for magic-byte sniffing). */
export const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(64, 1)]);

export const PDF = Buffer.from('%PDF-1.7\n%fake document');

export function isoDateFromNow(years: number): string {
  const d = new Date();
  d.setUTCFullYear(d.getUTCFullYear() + years);
  return d.toISOString().slice(0, 10);
}

/** A complete, valid set of personal details. */
export function completeDetails(overrides: Record<string, string> = {}) {
  return {
    fullName: 'Alice Nguyen',
    dateOfBirth: '1990-05-20',
    nationality: 'VN',
    addressLine1: '12 Nguyen Hue',
    city: 'Ho Chi Minh City',
    country: 'VN',
    idType: 'NATIONAL_ID',
    idNumber: '079090001234',
    idIssueDate: '2021-01-15',
    idExpiryDate: isoDateFromNow(5),
    ...overrides,
  };
}

export const STRONG_PASSWORD = 'Sup3rSecret!';
