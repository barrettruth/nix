import { pierreTheme } from "./themes.js";

export function diffStyleFromLocation() {
  return new URLSearchParams(window.location.search).get("style") === "split"
    ? "split"
    : "unified";
}

export function pierreDiffRenderOptions(overrides = {}) {
  return {
    diffIndicators: "bars",
    diffStyle: diffStyleFromLocation(),
    disableFileHeader: true,
    enableLineSelection: true,
    lineDiffType: "char",
    maxLineDiffLength: 500,
    theme: pierreTheme,
    ...overrides,
  };
}
