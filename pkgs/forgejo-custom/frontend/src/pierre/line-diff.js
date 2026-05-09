import { diffChars, diffWordsWithSpace } from "diff";

function cleanLastNewline(contents) {
  return contents.replace(/\n$|\r\n$/, "");
}

function pushOrJoinSpan({
  item,
  spans,
  enableJoin,
  isNeutral = false,
  isLastItem = false,
}) {
  const previous = spans.at(-1);
  if (!previous || isLastItem || !enableJoin) {
    spans.push([isNeutral ? 0 : 1, item.value]);
    return;
  }

  const previousIsNeutral = previous[0] === 0;
  if (
    isNeutral === previousIsNeutral ||
    (isNeutral && item.value.length === 1 && !previousIsNeutral)
  ) {
    previous[1] += item.value;
    return;
  }

  spans.push([isNeutral ? 0 : 1, item.value]);
}

function activeSpanRanges(spans) {
  const ranges = [];
  let offset = 0;
  for (const [active, value] of spans) {
    if (active === 1) ranges.push({ start: offset, end: offset + value.length });
    offset += value.length;
  }
  return ranges;
}

function changedSpans(deletionLine, additionLine, options) {
  if (
    deletionLine == null ||
    additionLine == null ||
    options.lineDiffType === "none"
  ) {
    return { additions: [], deletions: [] };
  }

  const cleanDeletion = cleanLastNewline(deletionLine);
  const cleanAddition = cleanLastNewline(additionLine);
  if (
    cleanDeletion.length > options.maxLineDiffLength ||
    cleanAddition.length > options.maxLineDiffLength
  ) {
    return { additions: [], deletions: [] };
  }

  const lineDiff =
    options.lineDiffType === "char"
      ? diffChars(cleanDeletion, cleanAddition)
      : diffWordsWithSpace(cleanDeletion, cleanAddition);
  const deletionSpans = [];
  const additionSpans = [];
  const enableJoin = options.lineDiffType === "word-alt";
  const lastItem = lineDiff.at(-1);

  for (const item of lineDiff) {
    const isLastItem = item === lastItem;
    if (!item.added && !item.removed) {
      pushOrJoinSpan({
        item,
        spans: deletionSpans,
        enableJoin,
        isNeutral: true,
        isLastItem,
      });
      pushOrJoinSpan({
        item,
        spans: additionSpans,
        enableJoin,
        isNeutral: true,
        isLastItem,
      });
    } else if (item.removed) {
      pushOrJoinSpan({ item, spans: deletionSpans, enableJoin, isLastItem });
    } else {
      pushOrJoinSpan({ item, spans: additionSpans, enableJoin, isLastItem });
    }
  }

  return {
    additions: activeSpanRanges(additionSpans),
    deletions: activeSpanRanges(deletionSpans),
  };
}

function unwrapLineDiffSpans(code) {
  const spans = code.querySelectorAll(".added-code, .removed-code");
  for (const span of spans) span.replaceWith(...span.childNodes);
  code.normalize();
}

function textSegments(root, start, end) {
  const segments = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let offset = 0;
  let node;

  while ((node = walker.nextNode())) {
    const nodeStart = offset;
    const nodeEnd = offset + node.data.length;
    const segmentStart = Math.max(start, nodeStart);
    const segmentEnd = Math.min(end, nodeEnd);

    if (segmentStart < segmentEnd) {
      segments.push({
        node,
        start: segmentStart - nodeStart,
        end: segmentEnd - nodeStart,
      });
    }

    offset = nodeEnd;
    if (offset >= end) break;
  }

  return segments;
}

function wrapTextRange(root, range, className) {
  if (range.end <= range.start) return;

  for (const segment of textSegments(root, range.start, range.end).reverse()) {
    let node = segment.node;
    if (segment.end < node.data.length) node.splitText(segment.end);
    if (segment.start > 0) node = node.splitText(segment.start);
    if (!node.data) continue;

    const wrapper = document.createElement("span");
    wrapper.className = className;
    node.parentNode.insertBefore(wrapper, node);
    wrapper.append(node);
  }
}

function codeText(code) {
  return cleanLastNewline(code.textContent ?? "");
}

function applyLineDiffPair(deletionCode, additionCode, options) {
  const spans = changedSpans(codeText(deletionCode), codeText(additionCode), {
    lineDiffType: options.lineDiffType,
    maxLineDiffLength: options.maxLineDiffLength,
  });

  for (const range of spans.deletions) {
    wrapTextRange(deletionCode, range, "removed-code");
  }
  for (const range of spans.additions) {
    wrapTextRange(additionCode, range, "added-code");
  }
}

export function lineDiffOptionKey(options) {
  return `${options.lineDiffType}:${options.maxLineDiffLength}`;
}

export function applyLineDiffs({ additions, deletions, options }) {
  for (const code of [...deletions, ...additions]) unwrapLineDiffSpans(code);

  const pairs = Math.min(deletions.length, additions.length);
  for (let index = 0; index < pairs; index += 1) {
    applyLineDiffPair(deletions[index], additions[index], options);
  }
}
