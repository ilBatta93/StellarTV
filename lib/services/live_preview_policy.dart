/// Preview never competes with pending local catalog or guide work.
bool livePreviewMustWait({
  required bool guideReady,
  required bool guideLoading,
  required bool catalogLoading,
}) => !guideReady || guideLoading || catalogLoading;
