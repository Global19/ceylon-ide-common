/********************************************************************************
 * Copyright (c) 2011-2017 Red Hat Inc. and/or its affiliates and others
 *
 * This program and the accompanying materials are made available under the 
 * terms of the Apache License, Version 2.0 which is available at
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0 
 ********************************************************************************/
import ceylon.collection {
    HashSet
}

import org.eclipse.ceylon.compiler.typechecker.tree {
    Tree,
    Visitor,
    Node
}
import org.eclipse.ceylon.ide.common.correct {
    importProposals
}
import org.eclipse.ceylon.ide.common.platform {
    CommonDocument,
    platformServices,
    TextChange
}
import org.eclipse.ceylon.ide.common.refactoring {
    DefaultRegion
}
import org.eclipse.ceylon.ide.common.util {
    OL=OccurrenceLocation,
    escaping
}
import org.eclipse.ceylon.model.typechecker.model {
    Declaration,
    Reference,
    Scope,
    Functional,
    TypeDeclaration,
    Unit,
    Class,
    Interface,
    Type,
    ModelUtil,
    FunctionOrValue,
    ParameterList,
    Parameter,
    TypeParameter,
    DeclarationWithProximity,
    Module,
    Value,
    Function,
    NothingType,
    Cancellable
}

import java.util {
    Collections,
    JList=List
}

shared interface InvocationCompletion {

    shared void addProgramElementReferenceProposal(Integer offset, String prefix,
        CompletionContext ctx, Declaration dec, Scope scope, Boolean isMember) {
        
        Unit? unit = ctx.lastCompilationUnit.unit;
        platformServices.completion.newInvocationCompletion {
            offset = offset;
            prefix = prefix;
            desc = dec.getName(unit);
            text = escaping.escapeName(dec, unit);
            dec = dec;
            pr = () => dec.reference;
            scope = scope;
            ctx = ctx;
            includeDefaulted = true;
            positionalInvocation = false;
            namedInvocation = false;
            inheritance = false;
            qualified = isMember;
            qualifyingDec = null;
        };
    }    

    // see InvocationCompletionProposal.addReferenceProposal()
    shared void addReferenceProposal(Tree.CompilationUnit cu,
        Integer offset, String prefix, CompletionContext ctx,
        DeclarationWithProximity dwp,
        Reference()? reference, Scope scope, OL? ol,
        Boolean isMember) {
        
        value unit = cu.unit;
        value dec = dwp.declaration;

        if (platformServices.completion.customizeReferenceProposals {
            cu = cu;
            offset = offset;
            prefix = prefix;
            ctx = ctx;
            dwp = dwp;
            reference = reference;
            scope = scope;
            ol = ol;
            isMember = isMember;
        }) {
            return;
        }

        //proposal with type args
        platformServices.completion.newInvocationCompletion {
            offset = offset;
            prefix = prefix;
            desc = getDescriptionFor2(dwp, unit, true);
            text = getTextFor(dec, unit);
            dec = dec;
            pr = reference;
            scope = scope;
            ctx = ctx;
            includeDefaulted = true;
            positionalInvocation = false;
            namedInvocation = false;
            inheritance
                    =  isLocation(ol, OL.upperBound)
                    || isLocation(ol, OL.\iextends)
                    || isLocation(ol, OL.\isatisfies);
            qualified = isMember;
            qualifyingDec = null;
        };

        if (!dec.parameterized) {
            // don't add another proposal below!
            return;
        }
        
        //proposal without type args
        value isAbstract 
                = if (is Class dec) 
                then dec.abstract 
                else dec is Interface;
        if (!isAbstract && 
            !isLocation(ol, OL.\iextends) &&
            !isLocation(ol, OL.\isatisfies) &&
            !isLocation(ol, OL.upperBound) ||
            !isLocation(ol, OL.classAlias) &&
            !isLocation(ol, OL.typeAlias)) {
            
            platformServices.completion.newInvocationCompletion {
                offset = offset;
                prefix = prefix;
                desc = getDescriptionFor2(dwp, unit, false);
                text = escaping.escapeName(dec, unit);
                dec = dec;
                pr = reference;
                scope = scope;
                ctx = ctx;
                includeDefaulted = true;
                positionalInvocation = false;
                namedInvocation = false;
                inheritance = false;
                qualified = isMember;
                qualifyingDec = null;
            };
        }
    }

    shared void addSecondLevelProposal(Integer offset, String prefix,
        CompletionContext ctx, Declaration dec, Scope scope, Boolean isMember,
        Reference reference, Type? requiredType, OL? ol, Cancellable cancellable) {
        
        value unit = ctx.lastCompilationUnit.unit;
        
        if (exists type = reference.type,
            exists td = type.declaration,
            is Value|Class|Interface dec) {

            value members
                    = switch (dec)
                    case (is Value)
                        //include inherited members
                        { for (dwp in td.getMatchingMemberDeclarations(
                                            unit, scope, "", 0, cancellable)
                                        .values())
                          if (!dwp.\ialias,
                              dwp.declaration is FunctionOrValue|Class)
                          dwp.declaration }
                    case (is Class|Interface)
                        //only include direct members
                        { for (member in td.members)
                          if (member.shared && member.name exists,
                              //constructors
                              member is FunctionOrValue
                              && member.constructor
                              //Java static members
                           || member is FunctionOrValue|Class
                              && member.static)
                          member };

            for (member in members.sort(byIncreasing(Declaration.name))) {
                if (member.abstraction) {
                    for (o in member.overloads) {
                        addSecondLevelProposalInternal {
                            offset = offset;
                            prefix = prefix;
                            ctx = ctx;
                            dec = dec;
                            scope = scope;
                            requiredType = requiredType;
                            ol = ol;
                            unit = unit;
                            type = type;
                            mwp = null;
                            member = o;
                        };
                    }
                } else {
                    addSecondLevelProposalInternal {
                        offset = offset;
                        prefix = prefix;
                        ctx = ctx;
                        dec = dec;
                        scope = scope;
                        requiredType = requiredType;
                        ol = ol;
                        unit = unit;
                        type = type;
                        mwp = null;
                        member = member;
                    };
                }
            }
        }
    }
    
    void addSecondLevelProposalInternal(
        Integer offset, String prefix,
        CompletionContext ctx,
        Declaration dec, Scope scope,
        Type? requiredType, OL? ol,
        Unit unit, Type type,
        DeclarationWithProximity? mwp,
        // sometimes we have no mwp so we also need the m
        Declaration member) {

        value noTypes = Collections.emptyList<Type>();

        value ptr = type.getTypedReference(member, noTypes);
        
        if (exists mt = ptr.type) {
            value cond 
                    = if (exists requiredType)
                    then withinBounds(requiredType, mt, scope)
                        || dec is Class 
                        && dec==requiredType.declaration
                    else true;
            
            if (cond) {
                value addParameterTypesInCompletions
                        = ctx.options
                            .parameterTypesInCompletion;
                value qualifier = dec.name + ".";
                value desc = qualifier 
                        + getPositionalInvocationDescriptionFor {
                            dwp = mwp;
                            dec = member;
                            ol = ol;
                            pr = ptr;
                            unit = unit;
                            includeDefaulted = false;
                            typeArgs = null;
                            addParameterTypesInCompletions 
                                    = addParameterTypesInCompletions;
                        };
                value text = qualifier 
                        + getPositionalInvocationTextFor {
                            dec = member;
                            ol = ol;
                            pr = ptr;
                            unit = unit;
                            includeDefaulted = false;
                            typeArgs = null;
                        };
                
                platformServices.completion.newInvocationCompletion {
                    offset = offset;
                    prefix = prefix;
                    desc = desc;
                    text = text;
                    dec = member;
                    pr = () => ptr;
                    scope = scope;
                    ctx = ctx;
                    includeDefaulted = true;
                    positionalInvocation = true;
                    namedInvocation = false;
                    inheritance 
                            = isLocation(ol, OL.upperBound)
                            || isLocation(ol, OL.\iextends)
                            || isLocation(ol, OL.\isatisfies);
                    qualified = true;
                    qualifyingDec = dec;
                };
            }
        }
    }
    
    // see InvocationCompletionProposal.addInvocationProposals()
    shared void addInvocationProposals(
        Integer offset, String prefix, CompletionContext ctx,
        DeclarationWithProximity? dwp,
        // sometimes we have no dwp, just a dec, so we have to handle that too
        Declaration dec, Reference reference,
        Scope scope, OL? ol,
        String? typeArgs, Boolean isMember) {

        if (is Functional dec) {

            value unit = ctx.lastCompilationUnit.unit;
            value exact =
                    prefixWithoutTypeArgs(prefix, typeArgs)
                        == dec.getName(unit);
            value inexactMatches = ctx.options.inexactMatches;
            value positional = exact
                    || "both"==inexactMatches
                    || "positional"==inexactMatches;
            value named = exact
                    || "both"==inexactMatches;

            if (positional || named,
                exists parameterList = dec.parameterLists[0]) {
                value ps = parameterList.parameters;
                value addParameterTypesInCompletions
                        = ctx.options
                            .parameterTypesInCompletion;

                value isAbstract
                        = if (is TypeDeclaration dec)
                        then dec.abstract
                        else false;

                value inheritance
                        = isLocation(ol, OL.upperBound) 
                        || isLocation(ol, OL.\iextends)
                        || isLocation(ol, OL.\isatisfies);

                if (positional,
                    parameterList.positionalParametersSupported,
                    !isAbstract 
                        || isLocation(ol, OL.\iextends)
                        || isLocation(ol, OL.classAlias)) {

                    value parameters 
                            = getParameters(parameterList, false, false);
                    if (ps.size() != parameters.size()) {
                        
                        platformServices.completion.newInvocationCompletion {
                            offset = offset;
                            prefix = prefix;
                            desc = getPositionalInvocationDescriptionFor {
                                    dwp = dwp;
                                    dec = dec;
                                    ol = ol;
                                    pr = reference;
                                    unit = unit;
                                    includeDefaulted = false;
                                    typeArgs = typeArgs;
                                    addParameterTypesInCompletions
                                            = addParameterTypesInCompletions;
                                };
                            text = getPositionalInvocationTextFor {
                                    dec = dec;
                                    ol = ol;
                                    pr = reference;
                                    unit = unit;
                                    includeDefaulted = false;
                                    typeArgs = typeArgs;
                                };
                            dec = dec;
                            pr = () => reference;
                            scope = scope;
                            ctx = ctx;
                            includeDefaulted = false;
                            positionalInvocation = true;
                            namedInvocation = false;
                            inheritance = inheritance;
                            qualified = isMember;
                            qualifyingDec = null;
                        };
                    }

                    platformServices.completion.newInvocationCompletion {
                        offset = offset;
                        prefix = prefix;
                        desc = getPositionalInvocationDescriptionFor {
                                dwp = dwp;
                                dec = dec;
                                ol = ol;
                                pr = reference;
                                unit = unit;
                                includeDefaulted = true;
                                typeArgs = typeArgs;
                                addParameterTypesInCompletions
                                        = addParameterTypesInCompletions;
                            };
                        text = getPositionalInvocationTextFor {
                                dec = dec;
                                ol = ol;
                                pr = reference;
                                unit = unit;
                                includeDefaulted = true;
                                typeArgs = typeArgs;
                            };
                        dec = dec;
                        pr = () => reference;
                        scope = scope;
                        ctx = ctx;
                        includeDefaulted = true;
                        positionalInvocation = true;
                        namedInvocation = false;
                        inheritance = inheritance;
                        qualified = isMember;
                        qualifyingDec = null;
                    };
                }
                if (named, 
                    parameterList.namedParametersSupported,
                    !isAbstract 
                            && !isLocation(ol, OL.\iextends) 
                            && !isLocation(ol, OL.classAlias)
                            && !dec.overloaded) {
                    
                    //if there is at least one parameter, 
                    //suggest a named argument invocation
                    value parameters 
                            = getParameters(parameterList, false, true);
                    if (ps.size() != parameters.size()) {
                        platformServices.completion.newInvocationCompletion {
                            offset = offset;
                            prefix = prefix;
                            desc = getNamedInvocationDescriptionFor {
                                    dec = dec;
                                    pr = reference;
                                    unit = unit;
                                    includeDefaulted = false;
                                    typeArgs = typeArgs;
                                    addParameterTypesInCompletions
                                            = addParameterTypesInCompletions;
                                };
                            text = getNamedInvocationTextFor {
                                    dec = dec;
                                    pr = reference;
                                    unit = unit;
                                    includeDefaulted = false;
                                    typeArgs = typeArgs;
                                };
                            dec = dec;
                            pr = () => reference;
                            scope = scope;
                            ctx = ctx;
                            includeDefaulted = false;
                            positionalInvocation = false;
                            namedInvocation = true;
                            inheritance = inheritance;
                            qualified = isMember;
                            qualifyingDec = null;
                        };
                    }
                    if (!ps.empty) {
                        platformServices.completion.newInvocationCompletion {
                            offset = offset;
                            prefix = prefix;
                            desc = getNamedInvocationDescriptionFor {
                                    dec = dec;
                                    pr = reference;
                                    unit = unit;
                                    includeDefaulted = true;
                                    typeArgs = typeArgs;
                                    addParameterTypesInCompletions
                                            = addParameterTypesInCompletions;
                                };
                            text = getNamedInvocationTextFor {
                                    dec = dec;
                                    pr = reference;
                                    unit = unit;
                                    includeDefaulted = true;
                                    typeArgs = typeArgs;
                                };
                            dec = dec;
                            pr = () => reference;
                            scope = scope;
                            ctx = ctx;
                            includeDefaulted = true;
                            positionalInvocation = false;
                            namedInvocation = true;
                            inheritance = inheritance;
                            qualified = isMember;
                            qualifyingDec = null;
                        };
                    }
                }
            }
        }
    }
    
    shared void addFakeShowParametersCompletion(Node node, CompletionContext ctx) {
        if (exists upToDateAndTypeChecked = ctx.typecheckedRootNode) {
            object extends Visitor() {
                shared actual void visit(Tree.InvocationExpression that) {
                    if (exists pal = that.positionalArgumentList 
                        else that.namedArgumentList, 
                        exists startIndex = pal.startIndex,
                        exists startIndex2 = node.startIndex, 
                        startIndex.intValue() == startIndex2.intValue(), 
                        is Tree.MemberOrTypeExpression primary = that.primary, 
                        exists decl = primary.declaration,
                        exists target = primary.target) {
                        
                        platformServices.completion.newParameterInfo {
                            offset = startIndex.intValue();
                            dec = decl;
                            producedReference = target;
                            scope = node.scope;
                            ctx = ctx;
                            namedInvocation 
                                    = pal is Tree.NamedArgumentList;
                        };
                    }
                    super.visit(that);
                }
            }.visit(upToDateAndTypeChecked);
        }
    }

    // see InvocationCompletionProposal.prefixWithoutTypeArgs
    String prefixWithoutTypeArgs(String prefix, String? typeArgs) 
            => if (exists typeArgs)
            then prefix.removeTerminal(typeArgs)
            else prefix;
}

shared abstract class InvocationCompletionProposal
    (variable Integer _offset, String prefix, String desc, String text,
    Declaration declaration, Reference()? producedReference, Scope scope,
    Tree.CompilationUnit cu, Boolean includeDefaulted, Boolean positionalInvocation,
    Boolean namedInvocation, Boolean inheritance, Boolean qualified,
    Declaration? qualifyingValue)
        extends AbstractCompletionProposal(_offset, prefix, desc, text) {
    
    shared formal void newNestedLiteralCompletionProposal(ProposalsHolder props, String val,
        Integer loc, Integer index);
    
    shared formal void newNestedCompletionProposal(ProposalsHolder props, Declaration dec,
        Declaration? qualifier, Integer loc, Integer index, Boolean basic, String op);
    
    shared String getNestedCompletionText(String op, Unit unit, Declaration dec,
        Declaration? qualifier, Boolean basic, Boolean description) {
        value sb = StringBuilder().append(op);
        sb.append(getProposedName(qualifier, dec, unit));
        if (dec is Functional, !basic) {
            appendPositionalArgs(dec, dec.reference, unit, sb, false,
                description, false);
        }
        return sb.string;
    }

    shared Integer adjustedOffset => offset;
    
    shared TextChange createChange(CommonDocument document) {
        value decs = HashSet<Declaration>();
        value change = platformServices.document.createTextChange("Complete Invocation", document);
        change.initMultiEdit();
        
        if (exists qualifyingValue) {
            importProposals.importDeclaration(decs, qualifyingValue, cu, scope);
        }
        if (!qualified) {
            importProposals.importDeclaration(decs, declaration, cu, scope);
        }
        if (positionalInvocation || namedInvocation) {
            importProposals.importCallableParameterParamTypes(declaration, decs, cu, scope);
        }
        value il = importProposals.applyImports(change, decs, cu, document, scope);
        change.addEdit(createEdit(document));
        offset += il;
        return change;
    }
    
    shared void activeLinkedMode(CommonDocument document, CompletionContext cpc, Cancellable? cancellable=null) {
        if (cpc.options.linkedModeArguments) {
            variable ParameterList? paramList = null;
            if (is Functional fd = declaration,
                positionalInvocation || namedInvocation) {
                
                value pls = fd.parameterLists;
                if (exists pl = pls[0],
                    !pl.parameters.empty) {
                    paramList = pl;
                }
            }
            if (exists pl = paramList) {
                value params = 
                        getParameters(pl, includeDefaulted, namedInvocation);
                if (!params.empty) {
                    enterLinkedMode(document, params, null, cpc, cancellable);
                    return; //NOTE: early exit!
                }
            }
            value typeParams = declaration.typeParameters;
            if (!typeParams.empty) {
                enterLinkedMode(document, null, typeParams, cpc, cancellable);
            }
        }
    }
    
    shared actual DefaultRegion getSelectionInternal(CommonDocument document) {
        value first = getFirstPosition();
        if (first <= 0) {
            //no arg list
            return super.getSelectionInternal(document);
        }
        value next = getNextPosition(document, first);
        if (next <= 0) {
            //an empty arg list
            return super.getSelectionInternal(document);
        }
        value middle = getCompletionPosition(first, next);
        variable value start = offset - prefix.size + first + middle;
        variable value len = next - middle;
        if (document.getText(start, len).trimmed=="{}") {
            start++;
            len = 0;
        }
        
        return DefaultRegion(start, len);
    }
    
    Integer getCompletionPosition(Integer first, Integer next) 
            => (text.span(first, first + next - 2).lastOccurrence(' ') else -1) + 1;
    
    shared Integer getFirstPosition() {
        value index 
                = if (namedInvocation)
                then text.firstOccurrence('{')
                else if (positionalInvocation)
                then text.firstOccurrence('(')
                else text.firstOccurrence('<');
        return (index else -1) + 1;
    }
    
    shared Integer getNextPosition(CommonDocument document, Integer lastOffset) {
        value loc = offset - prefix.size;
        variable value comma = -1;
        value start = loc + lastOffset;
        variable value end = loc + text.size - 1;
        if (text.endsWith(";")) {
            end--;
        }
        comma = findCharCount(1, document, start, end, ",;", "", true)
                - start;
        
        if (comma < 0) {
            value index 
                    = if (namedInvocation)
                    then text.lastOccurrence('}')
                    else if (positionalInvocation)
                    then text.lastOccurrence(')')
                    else text.lastOccurrence('>');
            return (index else -1) - lastOffset;
        }
        return comma;
    }
    
    shared void enterLinkedMode(CommonDocument document, 
        JList<Parameter>? params,
        JList<TypeParameter>? typeParams, 
        CompletionContext cpc,
        Cancellable? cancellable) {
        
        value proposeTypeArguments = !params exists;
        value paramCount 
                = proposeTypeArguments
                then (typeParams?.size() else 0)
                else (params?.size() else 0);
        if (paramCount == 0) {
            return;
        }
        try {
            value loc = offset - prefix.size;
            variable value first 
                    = getFirstPosition();
            if (first <= 0) {
                return; //no arg list
            }
            variable value next 
                    = getNextPosition(document, first);
            if (next <= 0) {
                return; //empty arg list
            }
            value linkedMode = platformServices.createLinkedMode(document);
            variable value seq = 0;
            variable value param = 0;
            while (next>0 && param<paramCount) {
                // if proposeTypeArguments is false, params *should* exist
                value voidParam 
                        = !proposeTypeArguments
                        && (params?.get(param)?.declaredVoid else false);
                if (proposeTypeArguments || positionalInvocation
                        //don't create linked positions for
                        //void callable parameters in named
                        //argument lists
                        || !voidParam) {
                    
                    value props = platformServices.completion.createProposalsHolder();
                    if (proposeTypeArguments) {
                        assert (exists typeParams);
                        addTypeArgumentProposals {
                            props = props;
                            tp = typeParams.get(seq);
                            loc = loc;
                            first = first;
                            index = seq;
                            cancellable = cancellable;
                        };
                    } else if (!voidParam || positionalInvocation) {
                        assert (exists params, exists p = params[param]);
                        addValueArgumentProposals {
                            props = props;
                            param = p;
                            loc = loc;
                            first = first;
                            index = seq;
                            last = param == params.size() - 1;
                            cpc = cpc;
                            cancellable = cancellable;
                            positionalInvocation = positionalInvocation;
                        };
                    }
                    value middle 
                            = getCompletionPosition(first, next);
                    variable value start = loc + first + middle;
                    variable value len = next - middle;
                    if (voidParam && !positionalInvocation) {
                        start++;
                        len = 0;
                    }
                    linkedMode.addEditableRegion {
                        start = start;
                        length = len;
                        exitSeqNumber = seq;
                        proposals = props;
                    };
                    first = first + next + 1;
                    next = getNextPosition(document, first);
                    seq++;
                }
                param++;
            }
            if (seq > 0) {
                linkedMode.install {
                    owner = this;
                    exitSeqNumber = seq;
                    exitPosition = loc + text.size;
                };
            }
        } catch (e) {
            e.printStackTrace();
        }
    }
    
    void addValueArgumentProposals(ProposalsHolder props, 
        Parameter param, Integer loc, Integer first, Integer index, 
        Boolean last, CompletionContext cpc, Cancellable? cancellable,
        Boolean positionalInvocation) {
        
        if (!param.model.dynamicallyTyped, 
            exists producedReference, 
            exists type =
                    let (tp = producedReference().getTypedParameter(param))
                    if (positionalInvocation) then tp.fullType else tp.type) {
            value unit = cu.unit;

            if (type.callable) {
//                completionManager.addAnonFunctionProposal(cpc, loc, type, unit);
                value header = anonFunctionHeader {
                    requiredType = type;
                    unit = unit;
                    param = param;
                };

                newNestedLiteralCompletionProposal {
                    props = props;
                    val = header + " => nothing";
                    loc = loc;
                    index = index;
                };

                if (param.declaredVoid) {
                    newNestedLiteralCompletionProposal {
                        props = props;
                        val = header + " {}";
                        loc = loc;
                        index = index;
                    };
                }
            }

            value proposals
                    = getSortedProposedValues {
                        scope = scope;
                        unit = unit;
                        exactName = param.name;
                        cancellable = cancellable;
                    };
            
            //very special case for print()
            value dname = declaration.qualifiedNameString;
            value print = "ceylon.language::print" == dname;
            if (print) {
                for (val in getAssignableLiterals(unit.stringType, unit)) {
                    newNestedLiteralCompletionProposal {
                        props = props;
                        val = val;
                        loc = loc;
                        index = index;
                    };
                }
            }
            
            //stuff defined in the same block, along with
            //stuff with fuzzily-matching name:
            for (dwp in proposals) {
                if (dwp.proximity <= 1) {
                    addValueArgumentProposal {
                        props = props;
                        p = param;
                        loc = loc;
                        index = index;
                        last = last;
                        type = type;
                        unit = unit;
                        dwp = dwp;
                        qualifier = null;
                        cpc = cpc;
                        cancellable = cancellable;
                    };
                }
            }
            
            //this:
            if (exists ci = ModelUtil.getContainingClassOrInterface(scope),
                ci.type.isSubtypeOf(type)) {
                newNestedLiteralCompletionProposal {
                    props = props;
                    val = "this";
                    loc = loc;
                    index = index;
                };
            }
            
            //literals:
            if (!print) {
                for (val in getAssignableLiterals(type, unit)) {
                    newNestedLiteralCompletionProposal {
                        props = props;
                        val = val;
                        loc = loc;
                        index = index;
                    };
                }
            }
            
            //stuff with lower proximity:
            for (dwp in proposals) {
                if (dwp.proximity > 1) {
                    addValueArgumentProposal {
                        props = props;
                        p = param;
                        loc = loc;
                        index = index;
                        last = last;
                        type = type;
                        unit = unit;
                        dwp = dwp;
                        qualifier = null;
                        cpc = cpc;
                        cancellable = cancellable;
                    };
                }
            }
        }
    }
    
    void addValueArgumentProposal(ProposalsHolder props, 
        Parameter p, Integer loc, Integer index, Boolean last, 
        Type type, Unit unit, 
        DeclarationWithProximity dwp, 
        DeclarationWithProximity? qualifier, 
        CompletionContext cpc,
        Cancellable? cancellable) {
        
        if (!qualifier exists && dwp.unimported) {
            return;
        }
        value dec = dwp.declaration;
        if (is NothingType dec) {
            return;
        }
        
        value pname = dec.unit.\ipackage.nameAsString;
        value isInLanguageModule 
                = !qualifier exists
                && pname == Module.languageModuleName;
        value qdec = qualifier?.declaration;
        
        if (is Value dec, 
            !(isInLanguageModule 
                && isIgnoredLanguageModuleValue(dec)), 
            exists vt = dec.type, !vt.nothing) {
            if (withinBounds(type, vt, scope)) {
                value isIterArg 
                        = namedInvocation 
                        && last
                        && unit.isIterableParameterType(type);
                value isVarArg 
                        = p.sequenced && positionalInvocation;
                newNestedCompletionProposal {
                    props = props;
                    dec = dec;
                    qualifier = qdec;
                    loc = loc;
                    index = index;
                    basic = false;
                    op = isIterArg || isVarArg then "*" else "";
                };
            }
            if (!qualifier exists, 
                cpc.options.chainLinkedModeArguments) {
                value members = 
                        dec.typeDeclaration
                           .getMatchingMemberDeclarations(unit, scope, "", 0, cancellable)
                           .values();
                for (mwp in members) {
                    addValueArgumentProposal {
                        props = props;
                        p = p;
                        loc = loc;
                        index = index;
                        last = last;
                        type = type;
                        unit = unit;
                        dwp = mwp;
                        qualifier = dwp;
                        cpc = cpc;
                        cancellable = cancellable;
                    };
                }
            }
        }
        
        if (is Function dec, 
            !dec.annotation, 
            !(isInLanguageModule 
                && isIgnoredLanguageModuleMethod(dec)), 
            exists mt = dec.type, !mt.nothing, 
            withinBounds(type, mt, scope)) {
            value isIterArg 
                    = namedInvocation 
                    && last
                    && unit.isIterableParameterType(type);
            value isVarArg = p.sequenced && positionalInvocation;
            newNestedCompletionProposal {
                props = props;
                dec = dec;
                qualifier = qdec;
                loc = loc;
                index = index;
                basic = false;
                op = isIterArg || isVarArg then "*" else "";
            };
        }
        
        if (is Class dec, 
            !dec.abstract && !dec.annotation, 
            !(isInLanguageModule 
                && isIgnoredLanguageModuleClass(dec)), 
            exists ct = dec.type, 
            withinBounds(type, ct, scope) 
                    || dec==type.declaration) {
            value isIterArg 
                    = namedInvocation 
                    && last
                    && unit.isIterableParameterType(type);
            value isVarArg 
                    = p.sequenced && positionalInvocation;
            if (dec.parameterList exists) {
                newNestedCompletionProposal {
                    props = props;
                    dec = dec;
                    qualifier = qdec;
                    loc = loc;
                    index = index;
                    basic = false;
                    op = isIterArg || isVarArg then "*" else "";
                };
            }
            for (m in dec.members) {
                if (m is FunctionOrValue 
                    && m.constructor 
                    && m.shared && m.name exists) {
                    newNestedCompletionProposal {
                        props = props;
                        dec = m;
                        qualifier = dec;
                        loc = loc;
                        index = index;
                        basic = false;
                        op = isIterArg || isVarArg then "*" else "";
                    };
                }
            }
        }
    }
    
    void addTypeArgumentProposals(ProposalsHolder props, 
        TypeParameter tp, Integer loc, Integer first, Integer index,
        Cancellable? cancellable) {
        
        value ed = cu.unit.exceptionDeclaration;
        
        for (dwp in getSortedProposedValues {
                scope = scope;
                unit = cu.unit;
                cancellable = cancellable;
        }) {
            value dec = dwp.declaration;
            value pname = dec.unit.\ipackage.nameAsString;
            value isInLanguageModule 
                    = pname == Module.languageModuleName;
            
            if (is TypeDeclaration dec, 
                !dwp.unimported,
                exists type = dec.type,
                !type.nothing && dec.typeParameters.empty &&
                !dec.annotation && !dec.inherits(ed), 
                !(isInLanguageModule 
                    && isIgnoredLanguageModuleType(dec)), 
                inheritance && tp.isSelfType() 
                    then scope == dec
                    else isInBounds(tp.satisfiedTypes, dec.type)) {
                newNestedCompletionProposal {
                    props = props;
                    dec = dec;
                    qualifier = null;
                    loc = loc;
                    index = index;
                    basic = true;
                    op = "";
                };
            }
        }
    }
    
}

