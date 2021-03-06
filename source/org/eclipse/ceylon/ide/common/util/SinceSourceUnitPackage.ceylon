/********************************************************************************
 * Copyright (c) 2011-2017 Red Hat Inc. and/or its affiliates and others
 *
 * This program and the accompanying materials are made available under the 
 * terms of the Apache License, Version 2.0 which is available at
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0 
 ********************************************************************************/
import org.eclipse.ceylon.ide.common.model {
    CeylonUnit
}
import org.eclipse.ceylon.model.typechecker.model {
    Package,
    Module,
    Declaration,
    Unit,
    Type,
    Annotation,
    Scope,
    DeclarationWithProximity,
    Import,
    TypeDeclaration,
    Cancellable
}

import java.lang {
    JString=String,
    JIterable=Iterable
}
import java.util {
    JList=List,
    JLinkedList=LinkedList,
    JMap=Map
}

shared class SingleSourceUnitPackage(modelPackage, fullPathOfSourceUnitToTypecheck)
        extends Package() {
    
    shared String fullPathOfSourceUnitToTypecheck;
    shared Package modelPackage;
    
    shared actual variable Module \imodule = modelPackage.\imodule;
    shared actual variable JList<JString> name = modelPackage.name;
    shared actual variable Boolean shared = modelPackage.shared;
    
    Boolean mustSearchUnitInSourceFile(Unit? modelUnit) =>
            if (is CeylonUnit modelUnit,
                exists fullPathOfModelSourceUnit = modelUnit.ceylonSourceFullPath)
            then fullPathOfModelSourceUnit == fullPathOfSourceUnitToTypecheck
            else false;
    
    Boolean mustSearchDeclarationInSourceFile(Declaration? modelDeclaration) =>
            if (exists modelDeclaration)
            then mustSearchUnitInSourceFile(modelDeclaration.unit)
            else true;
    
    shared actual Declaration? getDirectMember(String name,
        JList<Type> signature, Boolean ellipsis) =>
            let (Declaration? modelMember = modelPackage.getDirectMember(name, signature, ellipsis))
            if (mustSearchDeclarationInSourceFile(modelMember)) 
            then super.getDirectMember(name, signature, ellipsis) 
            else modelMember;
    
    shared actual Declaration? getMember(String name,
        JList<Type> signature, Boolean ellipsis) =>
            let (Declaration? modelMember = modelPackage.getMember(name, signature, ellipsis))
            if (mustSearchDeclarationInSourceFile(modelMember)) 
            then super.getMember(name, signature, ellipsis) 
            else modelMember;
    
    shared actual JList<Declaration> members {
        JLinkedList<Declaration> ret = JLinkedList<Declaration>();
        for (modelDeclaration in modelPackage.members) {
            if (! mustSearchDeclarationInSourceFile(modelDeclaration)) {
                ret.add(modelDeclaration);
            }
        }
        ret.addAll(super.members);
        return ret;
    }
    
    shared actual JIterable<Unit> units {
        JLinkedList<Unit> units = JLinkedList<Unit>();
        for (modelUnit in modelPackage.units) {
            if (!mustSearchUnitInSourceFile(modelUnit)) {
                units.add(modelUnit);
            }
        }
        for (u in super.units) {
            units.add(u);
        }
        return units;
    }
    
    shared actual JList<Annotation> annotations =>
            modelPackage.annotations;
    
    shared actual Scope? container => 
            modelPackage.container;
    
    shared actual Type? getDeclaringType(Declaration modelDeclaration) =>
            if (mustSearchDeclarationInSourceFile(modelDeclaration)) 
            then super.getDeclaringType(modelDeclaration) 
            else modelPackage.getDeclaringType(modelDeclaration);
    
    shared actual JMap<JString, DeclarationWithProximity> getImportableDeclarations(Unit modelUnit, 
        String startingWith, JList<Import> imports, Integer proximity, Cancellable cancellable) =>
            modelPackage.getImportableDeclarations(modelUnit, startingWith, imports, proximity, cancellable);
    
    shared actual TypeDeclaration? getInheritingDeclaration(Declaration d) =>
            modelPackage.getInheritingDeclaration(d);
    
    shared actual JMap<JString, DeclarationWithProximity> getMatchingDeclarations(
        Unit unit, String startingWith, Integer proximity, Cancellable? cancellable) =>
            super.getMatchingDeclarations(unit, startingWith, proximity, cancellable);
    
    shared actual Declaration? getMemberOrParameter(Unit modelUnit, String name,
        JList<Type> signature, Boolean ellipsis) =>
            let (Declaration? modelMember = modelPackage.getMemberOrParameter(modelUnit, name, signature, ellipsis))
            if (mustSearchDeclarationInSourceFile(modelMember)) 
            then super.getMemberOrParameter(modelUnit, name, signature, ellipsis) 
            else modelMember;
    
    shared actual String nameAsString =>
            modelPackage.nameAsString;
    
    shared actual String qualifiedNameString =>
            modelPackage.qualifiedNameString;
    
    shared actual Scope? scope =>
            modelPackage.scope;
    
    shared actual Unit? unit =>
            let(Unit? modelUnit=modelPackage.unit)
            if (mustSearchUnitInSourceFile(modelUnit))
            then super.unit 
            else modelUnit;
    assign unit {
        super.unit = unit;
    }
    
    shared actual Boolean isInherited(Declaration d) =>
            modelPackage.isInherited(d);
}
