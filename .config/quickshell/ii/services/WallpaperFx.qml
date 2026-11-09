pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Wallpaper change transitions, ported from pocket-dots' WallpaperFx.qml
 * (https://github.com/diegoMalagrida/pocket-dots, GPL-3.0).
 * The drawing happens in modules/ii/background/WallpaperFxLayer.qml, above the wallpaper image:
 * it fades in showing the old wallpaper, the real one is switched underneath, the shader
 * ends on the new one and the layer fades out again.
 * Maps come from scripts/wallfx/wallfx.py: "contagio" (pixel colonies, any wallpaper) or
 * "perfil" (character outline, needs `wallfx.py instalar`).
 */
Singleton {
    id: root

    property int msContagio: 1800
    property int msPerfil: 2000
    property int msFade: 130
    property int msSettle: 700 // Background repositions the new image for a moment after loading it
    property real glow: 0.9
    property real lineW: 1.5

    readonly property string scriptPath: `${FileUtils.trimFileProtocol(Directories.scriptPath)}/wallfx/wallfx-venv.sh`
    readonly property list<string> imageExtensions: ["jpg", "jpeg", "png", "webp", "avif", "bmp"]

    property string oldPath: ""
    property string newPath: ""
    property string kind: "contagio"
    property string fieldPath: ""
    property string linePath: ""
    // idle → choosing → loading → run (→ held, until Background shows the new one) → fadeout → idle
    property string phase: "idle"
    property real t: 0
    property real fade: 0
    property bool swapped: false
    property color ember: "orange"
    property color ink: "white"
    property real seed: 0
    readonly property bool active: phase !== "idle" && phase !== "choosing"

    // One WallpaperFxLayer per screen
    property var layers: []
    readonly property bool allLoaded: layers.length > 0 && layers.every(l => l.loaded)
    readonly property bool allSettled: layers.length > 0 && layers.every(l => l.backgroundSettled)
    function register(layer) {
        root.layers = root.layers.concat([layer]);
    }
    function unregister(layer) {
        root.layers = root.layers.filter(l => l !== layer);
    }
    onAllLoadedChanged: if (allLoaded) root.go()
    onAllSettledChanged: if (allSettled) settle.restart()

    function fileUrl(path) {
        return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
    }
    function isImage(path) {
        return root.imageExtensions.includes(path.split(".").pop().toLowerCase());
    }

    function lifted(c) {
        // A palette colour can be dark; the burning edge has to light up
        return Qt.hsla(c.hslHue, Math.max(c.hslSaturation, 0.55), Math.min(Math.max(c.hslLightness, 0.62), 0.82), 1);
    }

    /**
     * Change the wallpaper with a transition. paletteSource is an optional smaller
     * image (thumbnail) of the new wallpaper to pick the effect's colours from.
     */
    function change(path, paletteSource = "") {
        if (!path || path.length === 0) return;
        const current = Config.options.background.wallpaperPath;
        if (root.phase !== "idle") root.finish();
        if (root.layers.length === 0 || !current || current === path || !root.isImage(current) || !root.isImage(path)) {
            Wallpapers.apply(path);
            return;
        }
        root.oldPath = current;
        root.newPath = path;
        quantizer.source = root.fileUrl(paletteSource || path);
        root.phase = "choosing";
        chooseProc.exec([root.scriptPath, "elige", path]);
    }

    function fallback() {
        const path = root.newPath;
        root.finish();
        if (path) Wallpapers.apply(path);
    }

    function go() {
        if (root.phase !== "loading") return;
        watchdog.stop();
        // Captured now so the front doesn't change colour halfway through
        const chroma = c => c.hslSaturation * (1 - Math.abs(2 * c.hslLightness - 1));
        const light = c => 0.299 * c.r + 0.587 * c.g + 0.114 * c.b;
        let vivid = Appearance.m3colors.m3primary;
        let lightest = Appearance.m3colors.m3onBackground;
        for (let i = 0; i < quantizer.colors.length; i++) {
            const c = quantizer.colors[i];
            if (i === 0 || chroma(c) > chroma(vivid)) vivid = c;
            if (i === 0 || light(c) > light(lightest)) lightest = c;
        }
        root.ember = root.lifted(vivid);
        root.ink = Qt.hsla(lightest.hslHue, Math.min(lightest.hslSaturation, 0.35), Math.max(lightest.hslLightness, 0.88), 1);
        root.seed = Math.random() * 100;
        root.phase = "run";
        run.duration = root.kind === "perfil" ? root.msPerfil : root.msContagio;
        run.restart();
        fadeIn.restart();
    }

    // Uncover only when the transition has ended AND Background shows the new wallpaper
    function maybeFinish() {
        if (run.running) return;
        if (!root.swapped) {
            root.phase = "held";
            watchdog.restart();
            return;
        }
        root.phase = "fadeout";
        fadeOut.restart();
    }

    function finish() {
        fadeIn.stop();
        run.stop();
        fadeOut.stop();
        watchdog.stop();
        settle.stop();
        root.phase = "idle";
        root.fade = 0;
        root.t = 0;
        root.swapped = false;
        root.oldPath = "";
        root.newPath = "";
        root.fieldPath = "";
        root.linePath = "";
    }

    ColorQuantizer {
        id: quantizer
        depth: 3 // 2^3 = 8 colors
        rescaleSize: 64
    }

    // Prints "contagio <map> <smooth>" or "perfil <map> <line>"
    Process {
        id: chooseProc
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.phase !== "choosing") return;
                const parts = text.trim().split(" ");
                if (parts.length !== 3) {
                    // Output of a run that a newer change() replaced
                    if (!chooseProc.running) root.fallback();
                    return;
                }
                root.kind = parts[0] === "perfil" ? "perfil" : "contagio";
                root.fieldPath = parts[1];
                root.linePath = parts[2];
                root.phase = "loading";
                watchdog.restart();
                if (root.allLoaded) root.go();
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && !chooseProc.running && root.phase === "choosing") root.fallback();
        }
    }

    NumberAnimation {
        id: fadeIn
        target: root
        property: "fade"
        from: 0
        to: 1
        duration: root.msFade
        easing.type: Easing.OutQuad
        // Fully covered: switch the real wallpaper underneath
        onFinished: Wallpapers.apply(root.newPath)
    }
    // `t` is time, so it runs linear; the shader eases each phase itself
    NumberAnimation {
        id: run
        target: root
        property: "t"
        from: 0
        to: 1
        easing.type: Easing.Linear
        onFinished: root.maybeFinish()
    }
    NumberAnimation {
        id: fadeOut
        target: root
        property: "fade"
        from: 1
        to: 0
        duration: root.msFade
        easing.type: Easing.OutQuad
        onFinished: root.finish()
    }

    Timer {
        id: settle
        interval: root.msSettle
        onTriggered: {
            if (!root.allSettled || (root.phase !== "run" && root.phase !== "held")) return;
            root.swapped = true;
            root.maybeFinish();
        }
    }

    // The maps or images never load: change without the effect.
    // Background never reports the new wallpaper: step aside anyway.
    Timer {
        id: watchdog
        interval: 2500
        onTriggered: {
            if (root.phase === "loading") root.fallback();
            else root.finish();
        }
    }

    IpcHandler {
        target: "wallfx"

        function change(path: string): void {
            root.change(path);
        }

        function state(): string {
            return root.phase;
        }
    }
}
