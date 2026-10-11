const decoder = new TextDecoder();

/** Keep the queued payload as a view of its received frame, including its offset. */
export function decodePreviewFrame(data: ArrayBuffer): [string, Uint8Array] | undefined {
  const bytes = new Uint8Array(data);
  const separator = bytes.indexOf(44);
  if (separator <= 0) return undefined;
  return [decoder.decode(bytes.subarray(0, separator)), bytes.subarray(separator + 1)];
}
