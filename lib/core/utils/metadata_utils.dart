String cleanMetadata(String? value, {String fallback = 'Unknown'}) {
  if (value == null) {
    return fallback;
  }

  final cleaned = value.trim();

  if (cleaned.isEmpty || cleaned == '<unknown>') {
    return fallback;
  }

  return cleaned;
}
