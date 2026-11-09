import qs.services
import QtQuick

/**
 * Draws the wallpaper change transition for one screen. See services/WallpaperFx.qml.
 */
Item {
    id: root

    // How Background places its wallpaper image, so the hand-over doesn't jump
    property real zoom: 1
    property real fractionX: 0.5
    property real fractionY: 0.5
    // Background shows the new wallpaper
    property bool backgroundSettled: false
    readonly property bool loaded: oldImg.status === Image.Ready && newImg.status === Image.Ready
        && fieldImg.status === Image.Ready && lineImg.status === Image.Ready

    visible: WallpaperFx.active
    Component.onCompleted: WallpaperFx.register(root)
    Component.onDestruction: WallpaperFx.unregister(root)

    // Decoded at the size they are shown, not at the size of the file
    Image {
        id: oldImg
        visible: false
        asynchronous: true
        cache: false
        source: WallpaperFx.active ? WallpaperFx.fileUrl(WallpaperFx.oldPath) : ""
        sourceSize: Qt.size(root.width * root.zoom, root.height * root.zoom)
        fillMode: Image.PreserveAspectCrop
    }
    Image {
        id: newImg
        visible: false
        asynchronous: true
        cache: false
        source: WallpaperFx.active ? WallpaperFx.fileUrl(WallpaperFx.newPath) : ""
        sourceSize: Qt.size(root.width * root.zoom, root.height * root.zoom)
        fillMode: Image.PreserveAspectCrop
    }
    // The maps hold numbers, not colours: contagion's are read texel by texel, the outline's are interpolated
    Image {
        id: fieldImg
        visible: false
        asynchronous: true
        cache: false
        smooth: WallpaperFx.kind === "perfil"
        source: WallpaperFx.fileUrl(WallpaperFx.fieldPath)
    }
    Image {
        id: lineImg
        visible: false
        asynchronous: true
        cache: false
        source: WallpaperFx.fileUrl(WallpaperFx.linePath)
    }

    // Same placement as Background's wallpaper: cover the screen, times zoom, shifted by the parallax fraction
    function crop(img) {
        const iw = Math.max(img.implicitWidth, 1), ih = Math.max(img.implicitHeight, 1);
        const s = Math.max(root.width / iw, root.height / ih) * root.zoom;
        const w = iw * s, h = ih * s;
        const x = root.width > w ? (root.width - w) / 2 : -(w - root.width) * root.fractionX;
        const y = root.height > h ? (root.height - h) / 2 : -(h - root.height) * root.fractionY;
        return Qt.vector4d(-x / w, -y / h, root.width / w, root.height / h);
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.loaded
        opacity: WallpaperFx.fade
        property var oldTex: oldImg
        property var newTex: newImg
        property var fieldTex: fieldImg
        property var lineTex: lineImg
        property real t: WallpaperFx.t
        property real mode: WallpaperFx.kind === "perfil" ? 1 : 0
        property real sw: root.width
        property real sh: root.height
        property real fw: Math.max(fieldImg.implicitWidth, 1)
        property real fh: Math.max(fieldImg.implicitHeight, 1)
        property real lw: Math.max(lineImg.implicitWidth, 1)
        property real lh: Math.max(lineImg.implicitHeight, 1)
        property real glow: WallpaperFx.glow
        property real lineW: WallpaperFx.lineW
        property real sdRange: 16
        property real seed: WallpaperFx.seed
        property vector4d cropOld: root.crop(oldImg)
        property vector4d cropNew: root.crop(newImg)
        property color ember: WallpaperFx.ember
        property color ink: WallpaperFx.ink
        fragmentShader: Qt.resolvedUrl("shaders/wallfx.frag.qsb")
    }
}
