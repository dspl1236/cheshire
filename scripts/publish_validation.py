#!/usr/bin/env python3
"""Publish a validation run into the repo: docs/validation/<dataset>/

usage: publish_validation.py <dataset> [--panels N] [--width W]

Copies compare_stats.{csv,md} and compare_summary.json from data/out/<dataset>-hip/,
picks representative comparison panels (best / median / worst by 'within 1 %'), downscales
them to <width> px and writes an index.md with the numbers, the timing from both runs and the
embedded images. Everything under docs/validation is committed; data/ stays ignored.
"""
from __future__ import annotations
import argparse, csv, json, re, shutil
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def elapsed_cuda(ds: str) -> str:
    for p in (ROOT / "data" / "ref" / ds / "DepthMap").glob("*/0.status"):
        return f"{json.load(open(p))['elapsedTime']:.1f} s"
    return "n/a"


def elapsed_hip(ds: str) -> str:
    log = ROOT / "build" / f"run-{ds.replace('monstree-', '')}.log"
    if log.exists():
        m = re.findall(r"Task done in \(s\): ([0-9.]+)", log.read_text(errors="replace"))
        if m: return f"{float(m[-1]):.1f} s"
    return "n/a"


def main() -> None:
    ap = argparse.ArgumentParser(); ap.add_argument("dataset"); ap.add_argument("--panels", type=int, default=3); ap.add_argument("--width", type=int, default=1800)
    a = ap.parse_args()
    ds = a.dataset
    src = ROOT / "data" / "out" / f"{ds}-hip"
    dst = ROOT / "docs" / "validation" / ds
    dst.mkdir(parents=True, exist_ok=True)
    for f in ["compare_stats.csv", "compare_stats.md", "compare_summary.json"]:
        shutil.copy2(src / f, dst / f)
    rows = list(csv.DictReader(open(src / "compare_stats.csv")))
    rows.sort(key=lambda r: float(r["within_1pct"]))
    picks = [("worst", rows[0]), ("median", rows[len(rows) // 2]), ("best", rows[-1])][: a.panels]
    imgs = []
    for tag, r in picks:
        im = Image.open(src / "compare" / f"{r['view']}.png")
        w, h = im.size; nh = int(h * a.width / w)
        im = im.resize((a.width, nh), Image.LANCZOS)
        name = f"{tag}_{r['view']}.png"; im.save(dst / name, optimize=True)
        imgs.append((tag, r, name))
    summ = json.load(open(src / "compare_summary.json"))
    md = [f"# Validation: {ds}", "",
          "HIP (Cheshire, RX 9070, Windows) vs CUDA (Meshroom 2023.3, GTX 1080 Ti, Linux) on the same SfM,",
          "same undistorted images and the same DepthMap parameters. Metrics are per view over pixels valid in",
          "both maps: relative depth error |hip - cuda| / cuda.", "",
          "| | CUDA reference | HIP (Cheshire) |", "|---|---|---|",
          f"| DepthMap wall time | {elapsed_cuda(ds)} | {elapsed_hip(ds)} |",
          f"| views | {summ['views']} | {summ['views']} |", "",
          "## Summary", "",
          f"* views with mask agreement >= 95 %: **{summ['views_mask_agree_ge_0p95']} / {summ['views']}**",
          f"* median (over views) of the per-view median relative depth error: **{summ['median_of_view_median_rel']:.4f}**",
          f"* median (over views) of the fraction of pixels within 1 %: **{summ['median_of_view_within_1pct']:.3f}**",
          f"* worst view: {summ['min_within_1pct']:.3f} within 1 %; largest per-view p95: {summ['max_p95_rel']:.4f}",
          f"* strict criterion ({summ['criterion']}): **{'PASS' if summ['strict_pass'] else 'FAIL'}**", "",
          "## Visual comparison (left: CUDA, middle: HIP, right: |difference|, same depth scale)", ""]
    for tag, r, name in imgs:
        md += [f"### {tag}: view {r['view']} - {float(r['within_1pct']) * 100:.1f} % within 1 %, mask agreement {float(r['mask_agree']):.3f}", "", f"![{tag}]({name})", ""]
    md += ["## Per-view table", "", (src / "compare_stats.md").read_text()]
    (dst / "index.md").write_text("\n".join(md), encoding="utf-8", newline="\n")
    print("published", dst, "with", len(imgs), "panels")


if __name__ == "__main__":
    main()
