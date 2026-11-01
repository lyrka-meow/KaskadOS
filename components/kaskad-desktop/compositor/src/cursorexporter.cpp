/*
    SPDX-FileCopyrightText: 2026 KaskadOS contributors
    SPDX-License-Identifier: GPL-2.0-or-later
*/

#include <QColor>
#include <QCoreApplication>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QTemporaryDir>

#include "utils/cursorcolor.h"

namespace
{
constexpr quint32 XcursorMagic = 0x72756358;
constexpr quint32 XcursorImageType = 0xfffd0002;

quint32 read32(const QByteArray &data, qsizetype offset, bool *ok)
{
    if (offset < 0 || offset + 4 > data.size()) {
        *ok = false;
        return 0;
    }
    const auto *bytes = reinterpret_cast<const unsigned char *>(data.constData());
    return quint32(bytes[offset])
        | (quint32(bytes[offset + 1]) << 8)
        | (quint32(bytes[offset + 2]) << 16)
        | (quint32(bytes[offset + 3]) << 24);
}

void write32(QByteArray &data, qsizetype offset, quint32 value)
{
    auto *bytes = reinterpret_cast<unsigned char *>(data.data());
    bytes[offset] = static_cast<unsigned char>(value & 0xff);
    bytes[offset + 1] = static_cast<unsigned char>((value >> 8) & 0xff);
    bytes[offset + 2] = static_cast<unsigned char>((value >> 16) & 0xff);
    bytes[offset + 3] = static_cast<unsigned char>((value >> 24) & 0xff);
}

bool transformCursor(QByteArray &data, const QColor &accent, QString *error)
{
    bool ok = true;
    if (read32(data, 0, &ok) != XcursorMagic) {
        *error = QStringLiteral("not an Xcursor file");
        return false;
    }
    const quint32 headerSize = read32(data, 4, &ok);
    const quint32 tocCount = read32(data, 12, &ok);
    if (!ok || headerSize < 16 || tocCount > 4096 || qsizetype(headerSize) + qsizetype(tocCount) * 12 > data.size()) {
        *error = QStringLiteral("invalid Xcursor header");
        return false;
    }

    const QColor outline = KWin::CursorColor::contrastingOutline(accent);
    int imageCount = 0;
    quint64 visiblePixels = 0;
    for (quint32 i = 0; i < tocCount; ++i) {
        const qsizetype toc = qsizetype(headerSize) + qsizetype(i) * 12;
        const quint32 type = read32(data, toc, &ok);
        const quint32 position = read32(data, toc + 8, &ok);
        if (!ok || type != XcursorImageType) {
            continue;
        }
        const qsizetype chunk = position;
        const quint32 chunkHeader = read32(data, chunk, &ok);
        const quint32 chunkType = read32(data, chunk + 4, &ok);
        const quint32 width = read32(data, chunk + 16, &ok);
        const quint32 height = read32(data, chunk + 20, &ok);
        const quint32 xhot = read32(data, chunk + 24, &ok);
        const quint32 yhot = read32(data, chunk + 28, &ok);
        const qsizetype pixels = chunk + chunkHeader;
        const quint64 pixelCount = quint64(width) * quint64(height);
        if (!ok || chunkHeader < 36 || chunkType != XcursorImageType || width == 0 || height == 0 || width > 1024 || height > 1024
            || xhot >= width || yhot >= height || pixels < 0 || pixels > data.size()
            || pixelCount > quint64((data.size() - pixels) / 4)) {
            *error = QStringLiteral("invalid Xcursor image chunk");
            return false;
        }
        for (quint64 p = 0; p < pixelCount; ++p) {
            const qsizetype offset = pixels + qsizetype(p * 4);
            const quint32 before = read32(data, offset, &ok);
            if ((before >> 24) != 0) {
                ++visiblePixels;
            }
            write32(data, offset, KWin::CursorColor::recolorPixel(before, accent, outline));
        }
        ++imageCount;
    }
    if (!ok || imageCount == 0 || visiblePixels == 0) {
        *error = QStringLiteral("cursor has no visible image frames");
        return false;
    }
    return true;
}

bool writeTheme(const QString &basePath, const QString &outputPath, const QColor &accent, QString *error)
{
    const QDir base(basePath);
    if (!base.exists(QStringLiteral("cursors"))) {
        *error = QStringLiteral("base cursor theme is missing: %1").arg(basePath);
        return false;
    }

    const QString temporaryPath = outputPath + QStringLiteral(".new-%1").arg(QCoreApplication::applicationPid());
    QDir(temporaryPath).removeRecursively();
    if (!QDir().mkpath(temporaryPath + QStringLiteral("/cursors"))) {
        *error = QStringLiteral("cannot create output theme");
        return false;
    }

    const QDir sourceCursors(base.filePath(QStringLiteral("cursors")));
    const QFileInfoList entries = sourceCursors.entryInfoList(QDir::Files | QDir::NoDotAndDotDot);
    for (const QFileInfo &entry : entries) {
        const QString destination = temporaryPath + QStringLiteral("/cursors/") + entry.fileName();
        if (entry.isSymLink()) {
            const QString target = entry.symLinkTarget();
            const QString relativeTarget = sourceCursors.relativeFilePath(target);
            if (relativeTarget.startsWith(QStringLiteral("../")) || !QFile::link(relativeTarget, destination)) {
                *error = QStringLiteral("unsafe or broken alias: %1").arg(entry.fileName());
                QDir(temporaryPath).removeRecursively();
                return false;
            }
            continue;
        }
        QFile input(entry.absoluteFilePath());
        if (!input.open(QFile::ReadOnly)) {
            *error = QStringLiteral("cannot read %1").arg(entry.fileName());
            QDir(temporaryPath).removeRecursively();
            return false;
        }
        QByteArray data = input.readAll();
        if (!transformCursor(data, accent, error)) {
            *error = entry.fileName() + QStringLiteral(": ") + *error;
            QDir(temporaryPath).removeRecursively();
            return false;
        }
        QSaveFile output(destination);
        if (!output.open(QFile::WriteOnly) || output.write(data) != data.size() || !output.commit()) {
            *error = QStringLiteral("cannot atomically write %1").arg(entry.fileName());
            QDir(temporaryPath).removeRecursively();
            return false;
        }
    }

    QFile index(temporaryPath + QStringLiteral("/index.theme"));
    if (!index.open(QFile::WriteOnly | QFile::Truncate)) {
        *error = QStringLiteral("cannot write index.theme");
        QDir(temporaryPath).removeRecursively();
        return false;
    }
    index.write("[Icon Theme]\nName=Kaskad Dynamic Cursor\nComment=Bibata geometry with the Kaskad system accent\nInherits=KaskadCursorBase\n");
    index.close();

    QDir(outputPath).removeRecursively();
    QDir parent(QFileInfo(outputPath).absolutePath());
    if (!parent.rename(QFileInfo(temporaryPath).fileName(), QFileInfo(outputPath).fileName())) {
        *error = QStringLiteral("cannot activate generated cursor theme");
        QDir(temporaryPath).removeRecursively();
        return false;
    }
    return true;
}

bool verifyTheme(const QString &themePath, QString *error)
{
    static const QStringList required = {
        QStringLiteral("default"), QStringLiteral("left_ptr"), QStringLiteral("pointer"), QStringLiteral("text"),
        QStringLiteral("wait"), QStringLiteral("progress"), QStringLiteral("not-allowed"), QStringLiteral("move"),
        QStringLiteral("ns-resize"), QStringLiteral("ew-resize"), QStringLiteral("nesw-resize"), QStringLiteral("nwse-resize"),
        QStringLiteral("n-resize"), QStringLiteral("s-resize"), QStringLiteral("e-resize"), QStringLiteral("w-resize"),
    };
    const QDir cursors(themePath + QStringLiteral("/cursors"));
    for (const QString &name : required) {
        const QFileInfo info(cursors.filePath(name));
        if (!info.exists() || !info.isReadable()) {
            *error = QStringLiteral("required cursor shape is missing: %1").arg(name);
            return false;
        }
    }
    QFile arrow(cursors.filePath(QStringLiteral("left_ptr")));
    if (!arrow.open(QFile::ReadOnly)) {
        *error = QStringLiteral("default arrow is unreadable");
        return false;
    }
    QByteArray data = arrow.readAll();
    const QByteArray original = data;
    if (!transformCursor(data, QColor(QStringLiteral("#67d99a")), error) || data.isEmpty()) {
        return false;
    }
    Q_UNUSED(original)
    return true;
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QFile::ReadOnly) ? file.readAll() : QByteArray();
}
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QString base;
    QString output;
    QColor accent(QStringLiteral("#9fe0b4"));
    bool verifyOnly = false;
    bool selfTest = false;
    const QStringList arguments = app.arguments();
    for (int i = 1; i < arguments.size(); ++i) {
        if (arguments[i] == QStringLiteral("--base") && i + 1 < arguments.size()) {
            base = arguments[++i];
        } else if (arguments[i] == QStringLiteral("--output") && i + 1 < arguments.size()) {
            output = arguments[++i];
        } else if (arguments[i] == QStringLiteral("--accent") && i + 1 < arguments.size()) {
            accent = QColor(arguments[++i]);
        } else if (arguments[i] == QStringLiteral("--verify-only")) {
            verifyOnly = true;
        } else if (arguments[i] == QStringLiteral("--self-test")) {
            selfTest = true;
        } else {
            qCritical("Unknown or incomplete argument: %s", qPrintable(arguments[i]));
            return 2;
        }
    }
    if (base.isEmpty() || !accent.isValid()) {
        qCritical("Usage: kaskad-cursor-exporter --base PATH [--output PATH --accent COLOR] [--verify-only|--self-test]");
        return 2;
    }

    QString error;
    if (!verifyTheme(base, &error)) {
        qCritical("Cursor base validation failed: %s", qPrintable(error));
        return 1;
    }
    if (verifyOnly) {
        return 0;
    }
    if (selfTest) {
        QImage memorySample(3, 1, QImage::Format_ARGB32_Premultiplied);
        memorySample.setPixel(0, 0, qRgba(255, 255, 255, 255));
        memorySample.setPixel(1, 0, qRgba(0, 0, 0, 255));
        memorySample.setPixel(2, 0, qRgba(255, 0, 0, 255));
        const quint32 statusPixel = memorySample.pixel(2, 0);
        KWin::CursorColor::recolorImage(memorySample, QColor(QStringLiteral("#67d99a")));
        if (memorySample.pixelColor(0, 0) != QColor(QStringLiteral("#67d99a"))
            || memorySample.pixelColor(1, 0) != KWin::CursorColor::contrastingOutline(QColor(QStringLiteral("#67d99a")))
            || memorySample.pixel(2, 0) != statusPixel) {
            qCritical("Cursor self-test failed: in-memory semantic recoloring is inconsistent");
            return 1;
        }

        QTemporaryDir temporary;
        if (!temporary.isValid()
            || !writeTheme(base, temporary.filePath(QStringLiteral("green")), QColor(QStringLiteral("#67d99a")), &error)
            || !verifyTheme(temporary.filePath(QStringLiteral("green")), &error)
            || !writeTheme(base, temporary.filePath(QStringLiteral("violet")), QColor(QStringLiteral("#a884ff")), &error)
            || !verifyTheme(temporary.filePath(QStringLiteral("violet")), &error)) {
            qCritical("Cursor self-test failed: %s", qPrintable(error));
            return 1;
        }
        const QByteArray green = readFile(temporary.filePath(QStringLiteral("green/cursors/left_ptr")));
        const QByteArray violet = readFile(temporary.filePath(QStringLiteral("violet/cursors/left_ptr")));
        if (green.isEmpty() || violet.isEmpty() || green == violet) {
            qCritical("Cursor self-test failed: palette revisions produced identical output");
            return 1;
        }
        return 0;
    }
    if (output.isEmpty() || !writeTheme(base, output, accent, &error) || !verifyTheme(output, &error)) {
        qCritical("Cursor export failed: %s", qPrintable(error));
        return 1;
    }
    return 0;
}
