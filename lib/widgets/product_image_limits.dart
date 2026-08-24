/// Product gallery photo limits (must stay aligned with API `Product::MAX_IMAGES`).
class ProductImageLimits {
  static const int maxImages = 60;

  /// Upload in batches so shared hosts with low `max_file_uploads` still work.
  static const int uploadBatchSize = 12;
}
