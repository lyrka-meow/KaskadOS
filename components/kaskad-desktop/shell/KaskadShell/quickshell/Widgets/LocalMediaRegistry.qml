pragma Singleton

import QtQuick

Item {
    id: root

    property var sessions: ({})

    Component {
        id: sessionFactory
        LocalMediaSession {}
    }

    function sessionFor(instanceId, config) {
        if (!instanceId)
            return null;
        const existing = sessions[instanceId];
        if (existing)
            return existing;

        const cfg = config || {};
        const created = sessionFactory.createObject(root, {
            instanceId: instanceId,
            folderPath: cfg.localMusicFolder ?? "",
            recursive: cfg.localMusicRecursive ?? false,
            repeatMode: cfg.localMusicRepeatMode ?? "none",
            shuffle: cfg.localMusicShuffle ?? false,
            volume: cfg.localMusicVolume ?? 0.8
        });
        if (!created)
            return null;
        sessions[instanceId] = created;
        return created;
    }

    function remove(instanceId) {
        const session = sessions[instanceId];
        if (!session)
            return;
        session.stop();
        session.destroy();
        delete sessions[instanceId];
    }
}
