pragma Singleton
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

/**
 * Idle inhibitor ("Keep awake") service.
 *
 * Two mechanisms are used together:
 *  1. The Wayland idle-inhibit protocol on a tiny, invisible overlay layer surface.
 *     Hyprland (0.57) only evaluates a layer-surface inhibitor when it is created and
 *     on window focus changes, and ignores it while the layer's alpha is 0 (not yet
 *     faded in after mapping, or a top layer hidden under a fullscreen window).
 *     So the window lives on the overlay layer and the inhibitor is only armed a
 *     moment after the window has been mapped.
 *  2. A systemd idle inhibitor lock (systemd-inhibit --what=idle), which hypridle
 *     honours independently of compositor state. Visible in `systemd-inhibit --list`.
 */
Singleton {
    id: root

    property bool inhibit: false
    // True a moment after the inhibitor window has been mapped, so the compositor
    // sees a mapped, faded-in surface when the Wayland inhibitor is created.
    property bool windowReady: false

    Connections {
        target: Persistent
        function onReadyChanged() {
            if (!Persistent.isNewHyprlandInstance) {
                root.inhibit = Persistent.states.idle.inhibit;
            } else {
                Persistent.states.idle.inhibit = root.inhibit;
            }
        }
    }

    function toggleInhibit(active = null) {
        if (active !== null) {
            root.inhibit = active;
        } else {
            root.inhibit = !root.inhibit;
        }
        Persistent.states.idle.inhibit = root.inhibit;
    }

    // systemd idle lock, honoured by hypridle (unless general:ignore_systemd_inhibit is set).
    // `cat` holds the lock only while its stdin (owned by this process) is open, so the
    // lock is released even if quickshell is killed or restarted while inhibiting.
    Process {
        id: systemdInhibitor
        running: root.inhibit
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=idle", "--who=Quickshell", "--why=Keep awake toggle", "--mode=block", "cat"]
    }

    Timer {
        id: windowReadyTimer
        interval: 1500
        repeat: false
        onTriggered: root.windowReady = true
    }

    IdleInhibitor {
        id: idleInhibitor
        enabled: root.inhibit && root.windowReady
        window: PanelWindow {
            id: inhibitorWindow
            WlrLayershell.namespace: "quickshell:idleInhibitor"
            // Overlay keeps the layer at full alpha under fullscreen windows,
            // which Hyprland requires for the inhibitor to count.
            WlrLayershell.layer: WlrLayer.Overlay
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            anchors {
                right: true
                bottom: true
            }
            // Make it not interactable
            mask: Region {
                item: null
            }

            onBackingWindowVisibleChanged: {
                if (backingWindowVisible) {
                    windowReadyTimer.restart();
                } else {
                    windowReadyTimer.stop();
                    root.windowReady = false;
                }
            }
            Component.onCompleted: {
                if (backingWindowVisible) windowReadyTimer.restart();
            }
        }
    }
}
