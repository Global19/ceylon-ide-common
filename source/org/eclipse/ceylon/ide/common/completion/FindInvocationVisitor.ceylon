/********************************************************************************
 * Copyright (c) 2011-2017 Red Hat Inc. and/or its affiliates and others
 *
 * This program and the accompanying materials are made available under the 
 * terms of the Apache License, Version 2.0 which is available at
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0 
 ********************************************************************************/
import org.eclipse.ceylon.compiler.typechecker.tree {
    Visitor,
    Tree,
    Node
}
import org.eclipse.ceylon.model.typechecker.model {
    Scope
}
class FindInvocationVisitor(Node node) extends Visitor() {
    shared variable Tree.InvocationExpression? result = null;
    
    shared actual void visit(Tree.InvocationExpression that) {
        if (exists pal = that.positionalArgumentList, pal==node) {
            result = that;
        }
        if (exists nal = that.namedArgumentList, nal==node) {
            result = that;
        }
        super.visit(that);
    }

}


class FindInvocationVisitor2(Scope scope) extends Visitor() {
    shared variable Tree.InvocationExpression? result = null;

    shared actual void visit(Tree.InvocationExpression that) {
        if (exists pal = that.positionalArgumentList, pal.scope==scope) {
            result = that;
        }
        if (exists nal = that.namedArgumentList, nal.scope==scope) {
            result = that;
        }
        super.visit(that);
    }

}
