import org.eclipse.ceylon.ide.common.model.delta {
    madeInvisibleOutsideScope,
    madeVisibleOutsideScope,
    structuralChange
}
import ceylon.test {
    test
}
import test.org.eclipse.ceylon.ide.common.model.delta {
    comparePhasedUnits,
    PackageDescriptorDeltaMockup
}

test void sharePackage() {
    comparePhasedUnits {
        path = "dir/package.ceylon";
        oldContents =
                "package dir;
                 ";
        newContents =
                "shared package dir;
                 ";
        expectedDelta =
            PackageDescriptorDeltaMockup {
                changedElementString = "Package[dir]";
                changes = [ madeVisibleOutsideScope ];
            };
    };
}

test void unsharePackage() {
    comparePhasedUnits {
        path = "dir/package.ceylon";
        oldContents =
                "shared package dir;
                 ";
        newContents =
                "package dir;
                 ";
        expectedDelta =
                PackageDescriptorDeltaMockup {
            changedElementString = "Package[dir]";
            changes = [ madeInvisibleOutsideScope ];
        };
    };
}

test void changePackageName() {
    comparePhasedUnits {
        path = "dir/package.ceylon";
        oldContents =
                "shared package dir;
                 ";
        newContents =
                "shared package dir2;
                 ";
        expectedDelta =
                PackageDescriptorDeltaMockup {
            changedElementString = "Package[dir]";
            changes = [ structuralChange ];
        };
    };

    comparePhasedUnits {
        path = "dir/package.ceylon";
        oldContents =
                "package dir;
                 ";
        newContents =
                "shared package dir2;
                 ";
        expectedDelta =
                PackageDescriptorDeltaMockup {
            changedElementString = "Package[dir]";
            changes = [ structuralChange ];
        };
    };
}

test void noChangesInPackage() {
    comparePhasedUnits {
        path = "dir/package.ceylon";
        oldContents =
                "shared package dir;
                 ";
        newContents =
                "shared package dir;
                 ";
        expectedDelta =
                PackageDescriptorDeltaMockup {
            changedElementString = "Package[dir]";
            changes = [ ];
        };
    };
}

