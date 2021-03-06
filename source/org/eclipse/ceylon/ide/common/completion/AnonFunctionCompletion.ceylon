/********************************************************************************
 * Copyright (c) 2011-2017 Red Hat Inc. and/or its affiliates and others
 *
 * This program and the accompanying materials are made available under the 
 * terms of the Apache License, Version 2.0 which is available at
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0 
 ********************************************************************************/
import org.eclipse.ceylon.ide.common.doc {
    Icons
}
import org.eclipse.ceylon.ide.common.platform {
    platformServices
}
import org.eclipse.ceylon.ide.common.refactoring {
    DefaultRegion
}
import org.eclipse.ceylon.model.typechecker.model {
    Unit,
    Type,
    Parameter
}

shared interface AnonFunctionCompletion {

    shared void addAnonFunctionProposal(CompletionContext ctx, Integer offset,
        Type? requiredType, Parameter? parameter, Unit unit) {

        value header = anonFunctionHeader {
            requiredType = requiredType;
            unit = unit;
            param = parameter;
        };
        
        platformServices.completion.addProposal {
            ctx = ctx;
            offset = offset;
            description = header + " => nothing";
            prefix = "";
            icon = Icons.correction;
            selection = DefaultRegion {
                start = offset + header.size + 4;
                length = 7;
            };
        };
        
        if (exists parameter, parameter.declaredVoid) {
            platformServices.completion.addProposal {
                ctx = ctx;
                offset = offset;
                description = header + " {}";
                prefix = "";
                icon = Icons.correction;
                selection = DefaultRegion {
                    start = offset + header.size + 2;
                    length = 0;
                };
            };
        }
    }
}
