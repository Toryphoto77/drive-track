#!/usr/bin/env python3
"""Top and iso previews for enclosure v9. FRONT (-Y) is at the top of the plan views."""
from __future__ import annotations
import os
import numpy as np
import trimesh
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "previews")
os.makedirs(OUT, exist_ok=True)


def load(name):
    m = trimesh.load(os.path.join(HERE, name), force="mesh")
    if not isinstance(m, trimesh.Trimesh):
        m = trimesh.util.concatenate(tuple(m.geometry.values()))
    return m


def plot_top(mesh, path, title, zdir=1):
    # Look from +Z, put FRONT (small Y) at the top of the image by inverting Y.
    fig, ax = plt.subplots(figsize=(8, 10), dpi=140)
    # Use a 2D plot of the outline + a raster of zmax
    try:
        from trimesh.voxel import creation
    except Exception:
        pass
    # Simple: plot all faces as 2D polygons colored by mean z
    b = mesh.bounds
    ax.set_aspect("equal")
    # subsample faces if huge
    faces = mesh.faces
    verts = mesh.vertices
    step = max(1, len(faces) // 40000)
    zs = verts[faces[::step]].reshape(-1, 3)[:, 2]
    # draw as a scatter of vertices, plus the bounding plan
    # Better: matplotlib tripcolor
    x = verts[:, 0]
    y = verts[:, 1]
    z = verts[:, 2]
    ax.tripcolor(x, y, faces[::step], z[faces[::step]].mean(axis=1) if False else z[faces[::step][:, 0]],
                 shading="flat", cmap="copper", rasterized=True)
    # The above may fail; fallback
    ax.set_xlim(b[0, 0] - 2, b[1, 0] + 2)
    ax.set_ylim(b[1, 1] + 2, b[0, 1] - 2)  # invert Y: FRONT (small Y) at top
    ax.set_title(title)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm), FRONT at top")
    ax.annotate("FRONT", xy=(0.5 * (b[0, 0] + b[1, 0]), b[0, 1] + 1.0),
                ha="center", va="bottom", fontsize=9)
    ax.annotate("USB", xy=(0.5 * (b[0, 0] + b[1, 0]), b[1, 1] - 1.0),
                ha="center", va="top", fontsize=9)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    print("wrote", path)


def plot_top_safe(mesh, path, title):
    fig, ax = plt.subplots(figsize=(8, 10), dpi=140)
    b = mesh.bounds
    # 2D histogram / max-z image
    nx, ny = 700, 900
    x0, y0, x1, y1 = b[0, 0], b[0, 1], b[1, 0], b[1, 1]
    # sample vertices only (fast)
    xs, ys, zs = mesh.vertices[:, 0], mesh.vertices[:, 1], mesh.vertices[:, 2]
    # also use a coarse face-center cloud
    fc = mesh.triangles_center
    xs = np.concatenate([xs, fc[:, 0]])
    ys = np.concatenate([ys, fc[:, 1]])
    zs = np.concatenate([zs, fc[:, 2]])
    # raster: for each pixel, max z of points in bin
    H, xe, ye = np.histogram2d(xs, ys, bins=[nx, ny], range=[[x0, x1], [y0, y1]], weights=zs)
    C, _, _ = np.histogram2d(xs, ys, bins=[nx, ny], range=[[x0, x1], [y0, y1]])
    img = np.divide(H, C, out=np.full_like(H, np.nan), where=C > 0)
    # img is (x,y); imshow expects (y,x) with origin lower. Invert Y for FRONT at top.
    ax.imshow(
        img.T[::-1],
        extent=[x0, x1, y0, y1],  # we'll invert the axis
        origin="upper",  # with extent y0 at top if we pass origin upper? careful
        cmap="cividis",
        aspect="equal",
    )
    # With origin=upper, the first row of the array is at the top.
    # img.T[::-1] has y=y1 as first row? img.T shape (ny,nx), [::-1] flips y so first row is y=y1.
    # That's USB at top — WRONG. We want FRONT (y0) at top.
    # So use img.T without flip, origin=upper => first row y0 at top. YES.
    ax.clear()
    ax.imshow(
        img.T,
        extent=[x0, x1, y1, y0],  # y-axis runs from y1 (bottom) to y0 (top)
        origin="upper",
        cmap="cividis",
        aspect="equal",
    )
    ax.set_title(title)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm)")
    ax.annotate("FRONT", xy=(0.5 * (x0 + x1), y0), ha="center", va="bottom",
                fontsize=10, color="white",
                xytext=(0, 8), textcoords="offset points")
    ax.annotate("USB", xy=(0.5 * (x0 + x1), y1), ha="center", va="top",
                fontsize=10, color="white",
                xytext=(0, -8), textcoords="offset points")
    fig.tight_layout()
    fig.savefig(path, facecolor="white")
    plt.close(fig)
    print("wrote", path, "size", os.path.getsize(path))


def plot_iso(mesh, path, title, elev=32, azim=-50):
    fig = plt.figure(figsize=(8, 7), dpi=140)
    ax = fig.add_subplot(111, projection="3d")
    # downsample faces
    faces = mesh.faces
    verts = mesh.vertices
    step = max(1, len(faces) // 25000)
    tris = verts[faces[::step]]
    coll = Poly3DCollection(tris, linewidths=0.02, alpha=1.0)
    z = tris[:, :, 2].mean(axis=1)
    znorm = (z - z.min()) / (z.max() - z.min() + 1e-9)
    colors = plt.cm.cividis(znorm)
    coll.set_facecolor(colors)
    coll.set_edgecolor("none")
    ax.add_collection3d(coll)
    b = mesh.bounds
    ax.set_xlim(b[0, 0], b[1, 0])
    ax.set_ylim(b[0, 1], b[1, 1])
    ax.set_zlim(b[0, 2], b[1, 2])
    try:
        ax.set_box_aspect((b[1, 0] - b[0, 0], b[1, 1] - b[0, 1], b[1, 2] - b[0, 2]))
    except Exception:
        pass
    ax.view_init(elev=elev, azim=azim)
    ax.set_title(title)
    ax.set_xlabel("X")
    ax.set_ylabel("Y")
    ax.set_zlabel("Z")
    fig.tight_layout()
    fig.savefig(path, facecolor="white")
    plt.close(fig)
    print("wrote", path, "size", os.path.getsize(path))


def main():
    base = load("base-v9.stl")
    lid = load("lid-v9.stl")
    assy = load("assembled-v9-DO-NOT-PRINT.stl")
    plot_top_safe(base, os.path.join(OUT, "base-top.png"), "Enclosure v9 base — plan, FRONT at top")
    plot_top_safe(lid, os.path.join(OUT, "lid-top.png"), "Enclosure v9 lid — plan, FRONT at top (read lettering this way)")
    plot_iso(base, os.path.join(OUT, "base-iso.png"), "Enclosure v9 base")
    plot_iso(lid, os.path.join(OUT, "lid-iso.png"), "Enclosure v9 lid")
    plot_iso(assy, os.path.join(OUT, "assembled-iso-DO-NOT-PRINT.png"), "Enclosure v9 assembled (do not print)")


if __name__ == "__main__":
    main()
