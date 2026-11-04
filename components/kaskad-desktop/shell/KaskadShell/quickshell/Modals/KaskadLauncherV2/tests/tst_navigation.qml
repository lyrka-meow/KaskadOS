import QtQuick
import QtTest
import "../NavigationHelpers.js" as Nav
TestCase {
    name: "LauncherSectionNavigation"
    function test_previousSection() {
        const model = [
            {isHeader: true, sectionId: "a", section: {id: "a"}},
            {sectionId: "a"}, {sectionId: "a"},
            {isHeader: true, sectionId: "empty", section: {id: "empty"}},
            {isHeader: true, sectionId: "b", section: {id: "b"}},
            {sectionId: "b"}, {sectionId: "b"},
            {isHeader: true, sectionId: "c", section: {id: "c"}},
            {sectionId: "c"}
        ];
        compare(Nav.calculatePrevSectionIndex(model, 5), 1);
        compare(Nav.calculatePrevSectionIndex(model, 6), 1);
        compare(Nav.calculatePrevSectionIndex(model, 8), 5);
        compare(Nav.calculatePrevSectionIndex(model, 1), 1);
        compare(Nav.calculatePrevSectionIndex(model, 4), 1);
        compare(Nav.calculatePrevSectionIndex([], 0), 0);
        compare(Nav.calculateNextSectionIndex(model, 1), 5);
    }
}
