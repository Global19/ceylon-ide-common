import ceylon.collection {
    ArrayList
}

import com.redhat.ceylon.compiler.typechecker.context {
    PhasedUnit
}
import com.redhat.ceylon.compiler.typechecker.parser {
    CeylonLexer
}
import com.redhat.ceylon.compiler.typechecker.tree {
    Node,
    Tree,
    Visitor
}
import com.redhat.ceylon.ide.common.correct {
    DocumentChanges
}
import com.redhat.ceylon.ide.common.model {
    CeylonUnit
}
import com.redhat.ceylon.ide.common.platform {
    ImportProposalServicesConsumer
}
import com.redhat.ceylon.ide.common.typechecker {
    AnyProjectPhasedUnit
}
import com.redhat.ceylon.ide.common.util {
    nodes,
    FindReferencesVisitor,
    FindDeclarationNodeVisitor
}
import com.redhat.ceylon.model.typechecker.model {
    Declaration,
    FunctionOrValue,
    Setter,
    TypeAlias,
    ClassOrInterface,
    Unit,
    TypeParameter,
    Generic,
    Referenceable,
    Value
}

import java.util {
    JList=List,
    HashSet,
    Set
}

import org.antlr.runtime {
    CommonToken,
    Token
}

shared Boolean isInlineRefactoringAvailable(
    Referenceable? declaration, 
    Tree.CompilationUnit rootNode, 
    Boolean inSameProject) {
    
    if (is Declaration declaration,
        inSameProject) {
        switch (declaration)
        case (is FunctionOrValue) {
            return !declaration.parameter 
                    && !(declaration is Setter) 
                    && !declaration.default 
                    && !declaration.formal 
                    && !declaration.native 
                    && (declaration.typeDeclaration exists) 
                    && (!declaration.typeDeclaration.anonymous) 
                    && (declaration.toplevel 
                        || !declaration.shared 
                        || !declaration.formal && !declaration.default && !declaration.actual)
                    && (!declaration.unit == rootNode.unit 
                    //not a Destructure
                    || !(getDeclarationNode(rootNode, declaration) 
                            is Tree.Variable));
            //TODO: && !declaration is a control structure variable 
            //TODO: && !declaration is a value with lazy init
        }
        case (is TypeAlias) {
            return true;
        } 
        case (is ClassOrInterface) {
            return declaration.\ialias;
        }
        else {
            return false;
        }
    } else {
        return false;
    }
}

Tree.StatementOrArgument? getDeclarationNode(
    Tree.CompilationUnit declarationUnit, Declaration declaration) {
    
    value fdv = FindDeclarationNodeVisitor(declaration);
    declarationUnit.visit(fdv);
    return fdv.declarationNode;
}

Declaration original(Declaration d) {
    if (is Value d,
        exists od = d.originalDeclaration) {
        return original(od);
    }
    return d;
}

shared interface InlineRefactoring<ICompletionProposal, IDocument, InsertEdit, TextEdit, TextChange, Change>
        satisfies AbstractRefactoring<Change>
                & ImportProposalServicesConsumer<Nothing, ICompletionProposal, IDocument, InsertEdit, TextEdit, TextChange>
                & DocumentChanges<IDocument, InsertEdit, TextEdit, TextChange>
        given InsertEdit satisfies TextEdit {
    
    shared interface InlineData satisfies EditorData {
        shared formal Declaration declaration;
        shared formal Boolean justOne;
        shared formal Boolean delete;
        shared formal IDocument doc;
    }
    
    shared formal actual InlineData editorData;
    shared formal TextChange newFileChange(PhasedUnit pu);
    shared formal TextChange newDocChange(IDocument doc);
    shared formal void addChangeToChange(Change change, TextChange tc);

    shared Boolean isReference =>
            let (node = editorData.node)
            !node is Tree.Declaration 
            && nodes.getIdentifyingNode(node) is Tree.Identifier;
    
    shared actual Boolean enabled => true;

    shared actual Integer countReferences(Tree.CompilationUnit cu) { 
        value vis = FindReferencesVisitor(editorData.declaration);
        //TODO: don't count references which are being narrowed
        //      in a Tree.Variable, since they don't get inlined
        cu.visit(vis);
        return vis.nodeSet.size();
    }

    name => "Inline";

    "Returns a single error or a sequence of warnings."
    shared String|String[] checkAvailability() {
        value declaration = editorData.declaration;
        value unit = declaration.unit;
        value declarationUnit 
                = if (is CeylonUnit cu = unit)
                then cu.phasedUnit?.compilationUnit
                else null;
        
        if (!exists declarationUnit) {
            return "Compilation unit not found";
        }
        
        value declarationNode 
                = getDeclarationNode {
                    declarationUnit = declarationUnit;
                    declaration = editorData.declaration;
                };
        if (is Tree.AttributeDeclaration declarationNode,
            !declarationNode.specifierOrInitializerExpression exists) {

            return "Cannot inline forward declaration: " + declaration.name;
        }
        if (is Tree.MethodDeclaration declarationNode,
            !declarationNode.specifierExpression exists) {

            return "Cannot inline forward declaration: " + declaration.name;            
        }
        
        if (is Tree.AttributeGetterDefinition declarationNode) {
            value getterDefinition = declarationNode;
            value statements = getterDefinition.block.statements;
            if (statements.size() != 1) {
                return "Getter body is not a single statement: " + declaration.name;
            }
            
            if (!(statements.get(0) is Tree.Return)) {
                return "Getter body is not a return statement: " + declaration.name;
            }
        }
        
        if (is Tree.MethodDefinition declarationNode) {
            value statements = declarationNode.block.statements;
            if (statements.size() != 1) {
                return "Function body is not a single statement: " + declaration.name;
            }
            
            value statement = statements.get(0);
            if (declarationNode.type is Tree.VoidModifier) {
                if (!statement is Tree.ExpressionStatement) {
                    return "Function body is not an expression: " + declaration.name;
                }
            } else if (!statement is Tree.Return) {
                return "Function body is not a return statement: " + declaration.name;
            }
        }
        
        value warnings = ArrayList<String>();
        
        if (is Tree.AnyAttribute declarationNode) {
            value attribute = declarationNode;
            if (attribute.declarationModel.variable) {
                warnings.add("Inlined value is variable");
            }
        }
        
        if (exists declarationNode) {
            declarationNode.visit(object extends Visitor() {
                shared actual void visit(Tree.BaseMemberOrTypeExpression that) {
                    super.visit(that);
                    if (exists dec = that.declaration) {
                        if (declaration.shared, !dec.shared, !dec.parameter) {
                            warnings.add("Definition contains reference to " 
                                          + "unshared declaration: " + dec.name);
                        }
                    } else {
                        warnings.add("Definition contains unresolved reference");
                    }
                }
            });
        }
        
        return warnings.sequence();
    }

    shared actual Change build(Change change) {
        variable Tree.CompilationUnit? declarationUnit = null;
        variable JList<CommonToken>? declarationTokens = null;
        value editorTokens = editorData.tokens;
        value declaration = editorData.declaration;
        
        value unit = declaration.unit;
        if (searchInEditor()) {
            if (editorData.rootNode.unit == unit) {
                declarationUnit = editorData.rootNode;
                declarationTokens = editorTokens;
            }
        }
        
        if (!declarationUnit exists) {
            for (pu in getAllUnits()) {
                if (pu.unit == unit) {
                    declarationUnit = pu.compilationUnit;
                    declarationTokens = pu.tokens;
                    break;
                }
            }
        }
        
        if (exists declUnit = declarationUnit,
            exists declTokens = declarationTokens,
            is Tree.Declaration declarationNode 
                    = getDeclarationNode(declUnit, 
                        editorData.declaration)) {

            value term = getInlinedTerm(declarationNode);
        
            for (phasedUnit in getAllUnits()) {
                if (searchInFile(phasedUnit)
                    && affectsUnit(phasedUnit.unit)) {
                    assert (is AnyProjectPhasedUnit phasedUnit);
                    inlineInFile {
                        tfc = newFileChange(phasedUnit);
                        parentChange = change;
                        declarationNode = declarationNode;
                        declarationUnit = declUnit;
                        term = term;
                        declarationTokens = declTokens;
                        rootNode = phasedUnit.compilationUnit;
                        tokens = phasedUnit.tokens;
                    };
                }
            }

            if (searchInEditor() 
                && affectsUnit(editorData.rootNode.unit)) {
                inlineInFile {
                    tfc = newDocChange(editorData.doc);
                    parentChange = change;
                    declarationNode = declarationNode;
                    declarationUnit = declUnit;
                    term = term;
                    declarationTokens = declTokens;
                    rootNode = editorData.rootNode;
                    tokens = editorTokens;
                };
            }
        }
        
        return change;
    }

    Boolean affectsUnit(Unit unit) {
        return editorData.delete && unit == editorData.declaration.unit
                || !editorData.justOne  
                || unit == editorData.node.unit;
    }

    Boolean addImports(TextChange change, Tree.Declaration declarationNode,
        Tree.CompilationUnit cu) {
        
        value decPack = declarationNode.unit.\ipackage;
        value filePack = cu.unit.\ipackage;
        variable Boolean importedFromDeclarationPackage = false;

        class AddImportsVisitor(already) extends Visitor() {
            Set<Declaration> already;
            
            shared actual void visit(Tree.BaseMemberOrTypeExpression that) {
                super.visit(that);
                if (exists dec = that.declaration) {
                    importProposals.importDeclaration(already, dec, cu);
                    value refPack = dec.unit.\ipackage;
                    importedFromDeclarationPackage = 
                            importedFromDeclarationPackage
                            || refPack.equals(decPack)
                            && !decPack.equals(filePack); //unnecessary
                }
            }
        }
        
        value already = HashSet<Declaration>();
        value aiv = AddImportsVisitor(already);
        declarationNode.visit(aiv);
        importProposals.applyImports {
            change = change;
            declarations = already;
            rootNode = cu;
            doc = editorData.doc;
            declarationBeingDeleted 
                    = declarationNode.declarationModel;
        };
        return importedFromDeclarationPackage;
    }

    void inlineInFile(TextChange tfc, Change parentChange, 
        Tree.Declaration declarationNode, Tree.CompilationUnit declarationUnit, 
        Node term, JList<CommonToken> declarationTokens, Tree.CompilationUnit rootNode,
        JList<CommonToken> tokens) {
        
        initMultiEditChange(tfc);
        inlineReferences(declarationNode, declarationUnit, term, 
            declarationTokens, rootNode, tokens, tfc);
        value inlined = hasChildren(tfc);
        deleteDeclaration(declarationNode, declarationUnit, rootNode, tokens, tfc);
        value importsAdded = inlined && addImports(tfc, declarationNode, rootNode);
        
        deleteImports(tfc, declarationNode, rootNode, tokens, importsAdded);
        if (hasChildren(tfc)) {
            addChangeToChange(parentChange, tfc);
        }
    }

    void deleteImports(TextChange tfc, Tree.Declaration declarationNode, 
        Tree.CompilationUnit cu, JList<CommonToken> tokens,
        Boolean importsAddedToDeclarationPackage) {
        
        if (exists il = cu.importList) {
            for (i in il.imports) {
                value list = i.importMemberOrTypeList.importMemberOrTypes;
                for (imt in list) {
                    if (exists d = imt.declarationModel, 
                        d == declarationNode.declarationModel) {
                        if (list.size() == 1 
                            && !importsAddedToDeclarationPackage) {
                            //delete the whole import statement
                            addEditToChange(tfc, 
                                newDeleteEdit {
                                    start = i.startIndex.intValue();
                                    length = i.distance.intValue();
                                });
                        } else {
                            //delete just the item in the import statement...
                            addEditToChange(tfc, 
                                newDeleteEdit {
                                    start = imt.startIndex.intValue();
                                    length = imt.distance.intValue();
                                });
                            //...along with a comma before or after
                            value ti = nodes.getTokenIndexAtCharacter(tokens,
                                imt.startIndex.intValue());
                            
                            variable CommonToken prev = tokens.get(ti - 1);
                            if (prev.channel == CommonToken.\iHIDDEN_CHANNEL) {
                                prev = tokens.get(ti - 2);
                            }
                            
                            variable CommonToken next = tokens.get(ti + 1);
                            if (next.channel == CommonToken.\iHIDDEN_CHANNEL) {
                                next = tokens.get(ti + 2);
                            }
                            
                            if (prev.type == CeylonLexer.\iCOMMA) {
                                addEditToChange(tfc, 
                                    newDeleteEdit {
                                        start = prev.startIndex;
                                        length = imt.startIndex.intValue() - prev.startIndex;
                                    });
                            } else if (next.type == CeylonLexer.\iCOMMA) {
                                addEditToChange(tfc, 
                                    newDeleteEdit {
                                        start = imt.endIndex.intValue();
                                        length = next.stopIndex - imt.endIndex.intValue() + 1;
                                    });
                            }
                        }
                    }
                }
            }
        }
    }
    
    void deleteDeclaration(Tree.Declaration declarationNode,
        Tree.CompilationUnit declarationUnit, Tree.CompilationUnit cu,
        JList<CommonToken> tokens, TextChange tfc) {
        
        if (editorData.delete 
            && cu.unit == declarationUnit.unit) {

            variable value from = declarationNode.token;
            value anns = declarationNode.annotationList;
            if (!anns.annotations.empty) {
                from = anns.annotations.get(0).token;
            }
            
            value prevIndex = from.tokenIndex - 1;
            if (prevIndex >= 0, 
                exists tok = tokens.get(prevIndex),
                tok.channel == Token.\iHIDDEN_CHANNEL) {
                from = tok;
            }
            
            if (is CommonToken t = from) {
                addEditToChange(tfc, 
                    newDeleteEdit {
                        start = t.startIndex;
                        length = declarationNode.endIndex.intValue() - t.startIndex;
                    });
            }
        }
    }

    Node getInlinedTerm(Tree.Declaration declarationNode) {
        switch (declarationNode)
        case (is Tree.AttributeDeclaration) {
            return declarationNode.specifierOrInitializerExpression.expression.term;
        }
        case (is Tree.MethodDefinition) {
            value statements = declarationNode.block.statements;
            if (declarationNode.type is Tree.VoidModifier) {
                //TODO: in the case of a void method, tolerate 
                //      multiple statements , including control
                //      structures, not just expression statements
                if (!isSingleExpression(statements)) {
                    throw Exception("method body is not a single expression statement");
                }
                
                assert(is Tree.ExpressionStatement e = statements[0]);
                return e.expression.term;
            } else {
                if (!isSingleReturn(statements)) {
                    throw Exception("method body is not a single expression statement");
                }
                
                assert (is Tree.Return ret = statements[0]);
                return ret.expression.term;
            }
        }
        case (is Tree.MethodDeclaration) {
            return declarationNode.specifierExpression.expression.term;
        }
        case (is Tree.AttributeGetterDefinition) {
            value statements = declarationNode.block.statements;
            if (!isSingleReturn(statements)) {
                throw Exception("getter body is not a single expression statement");
            }
            
            assert(is Tree.Return r 
                = declarationNode.block.statements[0]);
            return r.expression.term;
        }
        case (is Tree.ClassDeclaration) {
            return declarationNode.classSpecifier;
        }
        case (is Tree.InterfaceDeclaration) {
            return declarationNode.typeSpecifier;
        }
        case (is Tree.TypeAliasDeclaration) {
            return declarationNode.typeSpecifier;
        } else {
            throw Exception("not a value, function, or type alias");
        }
    }

    Boolean isSingleExpression(JList<Tree.Statement> statements) {
        return statements.size() == 1
                && statements.get(0) is Tree.ExpressionStatement;
    }
    
    Boolean isSingleReturn(JList<Tree.Statement> statements) {
        return statements.size() == 1
                && statements.get(0) is Tree.Return;
    }

    void inlineReferences(Tree.Declaration declarationNode, 
        Tree.CompilationUnit declarationUnit, Node definition, 
        JList<CommonToken> declarationTokens, Tree.CompilationUnit pu, 
        JList<CommonToken> tokens, TextChange tfc) {
        
        if (is Tree.AnyAttribute declarationNode,
            is Tree.Term expression = definition) {
            inlineAttributeReferences {
                rootNode = pu;
                tokens = tokens;
                term = expression;
                declarationTokens = declarationTokens;
                tfc = tfc;
            };
        } else if (is Tree.AnyMethod method = declarationNode,
                   is Tree.Term expression = definition) {
            inlineFunctionReferences {
                pu = pu;
                tokens = tokens;
                term = expression;
                decNode = method;
                declarationTokens = declarationTokens;
                tfc = tfc;
            };
        } else if (is Tree.ClassDeclaration classAlias = declarationNode,
                   is Tree.ClassSpecifier spec = definition) {
            inlineClassAliasReferences {
                pu = pu;
                tokens = tokens;
                term = spec.invocationExpression;
                type = spec.type;
                decNode = classAlias;
                declarationTokens = declarationTokens;
                tfc = tfc;
            };
        } else if (is Tree.TypeAliasDeclaration|Tree.InterfaceDeclaration declarationNode,
                   is Tree.TypeSpecifier definition) {
            inlineTypeAliasReferences {
                pu = pu;
                tokens = tokens;
                term = definition.type;
                declarationTokens = declarationTokens;
                tfc = tfc;
            };
        }
    }

    void inlineFunctionReferences(Tree.CompilationUnit pu, JList<CommonToken> tokens,
        Tree.Term term, Tree.AnyMethod decNode, JList<CommonToken> declarationTokens,
        TextChange tfc) {
        
        object extends Visitor() {
            variable Boolean needsParens = false;
            shared actual void visit(Tree.InvocationExpression that) {
                super.visit(that);
                value primary = that.primary;
                if (is Tree.MemberOrTypeExpression primary) {
                    inlineDefinition {
                        tokens = tokens;
                        declarationTokens = declarationTokens;
                        definition = term;
                        tfc = tfc;
                        invocation = that;
                        reference = primary;
                        needsParens = needsParens;
                    };
                }
            }
            
            shared actual void visit(Tree.MemberOrTypeExpression that) {
                super.visit(that);
                value dec = that.declaration;
                if (!that.directlyInvoked && inlineRef(that, dec)) {
                    value text = StringBuilder();
                    if (decNode.declarationModel.declaredVoid) {
                        text.append("void ");
                    }
                    
                    for (pl in decNode.parameterLists) {
                        text.append(nodes.text(pl, declarationTokens));
                    }
                    
                    text.append(" => ");
                    text.append(nodes.text(term, declarationTokens));
                    addEditToChange(tfc, 
                        newReplaceEdit {
                            start = that.startIndex.intValue();
                            length = that.distance.intValue();
                            text = text.string;
                        });
                }
            }
            
            shared actual void visit(Tree.OperatorExpression that) {
                value onp = needsParens;
                needsParens = true;
                super.visit(that);
                needsParens = onp;
            }
            
            shared actual void visit(Tree.StatementOrArgument that) {
                value onp = needsParens;
                needsParens = false;
                super.visit(that);
                needsParens = onp;
            }
            
            shared actual void visit(Tree.Expression that) {
                value onp = needsParens;
                needsParens = false;
                super.visit(that);
                needsParens = onp;
            }
        }.visit(pu);
    }

    void inlineTypeAliasReferences(Tree.CompilationUnit pu, 
        JList<CommonToken> tokens, Tree.Type term, 
        JList<CommonToken> declarationTokens, TextChange tfc) {
        
        object extends Visitor() {
            shared actual void visit(Tree.SimpleType that) {
                super.visit(that);
                inlineDefinition {
                    tokens = tokens;
                    declarationTokens = declarationTokens;
                    definition = term;
                    tfc = tfc;
                    invocation = null;
                    reference = that;
                    needsParens = false;
                };
            }
        }.visit(pu);
    }

    void inlineClassAliasReferences(Tree.CompilationUnit pu, 
        JList<CommonToken> tokens, Tree.InvocationExpression term,
        Tree.Type type, Tree.ClassDeclaration decNode,
        JList<CommonToken> declarationTokens, TextChange tfc) {
        
        object extends Visitor() {
            variable Boolean needsParens = false;

            shared actual void visit(Tree.SimpleType that) {
                super.visit(that);
                inlineDefinition {
                    tokens = tokens;
                    declarationTokens = declarationTokens;
                    definition = type;
                    tfc = tfc;
                    invocation = null;
                    reference = that;
                    needsParens = false;
                };
            }
            
            shared actual void visit(Tree.InvocationExpression that) {
                super.visit(that);
                value primary = that.primary;
                if (is Tree.MemberOrTypeExpression primary) {
                    value mte = primary;
                    inlineDefinition {
                        tokens = tokens;
                        declarationTokens = declarationTokens;
                        definition = term;
                        tfc = tfc;
                        invocation = that;
                        reference = mte;
                        needsParens = needsParens;
                    };
                }
            }
            
            shared actual void visit(Tree.MemberOrTypeExpression that) {
                super.visit(that);
                value d = that.declaration;
                if (!that.directlyInvoked, inlineRef(that, d)) {
                    value text = StringBuilder();
                    if (decNode.declarationModel.declaredVoid) {
                        text.append("void ");
                    }
                    text.append(nodes.text(decNode.parameterList, declarationTokens));
                    text.append(" => ");
                    text.append(nodes.text(term, declarationTokens));
                    addEditToChange(tfc, 
                        newReplaceEdit {
                            start = that.startIndex.intValue();
                            length = that.distance.intValue();
                            text = text.string;
                        });
                }
            }
            
            shared actual void visit(Tree.OperatorExpression that) {
                value onp = needsParens;
                needsParens = true;
                super.visit(that);
                needsParens = onp;
            }
            
            shared actual void visit(Tree.StatementOrArgument that) {
                value onp = needsParens;
                needsParens = false;
                super.visit(that);
                needsParens = onp;
            }
            
            shared actual void visit(Tree.Expression that) {
                value onp = needsParens;
                needsParens = false;
                super.visit(that);
                needsParens = onp;
            }
        }.visit(pu);
    }

    void inlineAttributeReferences(Tree.CompilationUnit rootNode, 
        JList<CommonToken> tokens, Tree.Term term, 
        JList<CommonToken> declarationTokens, TextChange tfc) {
        
        object extends Visitor() {
            variable value needsParens = false;
            variable value disabled = false;
            
            shared actual void visit(Tree.Variable that) {
                value dec = that.declarationModel;
                if (that.type is Tree.SyntheticVariable,
                    exists id = that.identifier,
                    original(dec) == editorData.declaration,
                    editorData.delete) {
                    disabled = true;
                    addEditToChange(tfc, 
                        newInsertEdit {
                            position = id.startIndex.intValue();
                            text = id.text + " = ";
                        });
                }
                super.visit(that);
            }
            
            shared actual void visit(Tree.Body that) {
                if (!disabled) {
                    super.visit(that);
                }
                disabled = false;
            }
            
            shared actual void visit(Tree.ElseClause that) {
                //don't re-visit the Variable!
                if (exists block = that.block) { 
                    block.visit(this);
                }
                if (exists expression = that.expression) { 
                    expression.visit(this);
                }
            }
            
            shared actual void visit(Tree.MemberOrTypeExpression that) {
                super.visit(that);
                inlineDefinition {
                    tokens = tokens;
                    declarationTokens = declarationTokens;
                    definition = term;
                    tfc = tfc;
                    invocation = null;
                    reference = that;
                    needsParens = needsParens;
                };
            }
            
            shared actual void visit(Tree.OperatorExpression that) {
                value onp = needsParens;
                needsParens = true;
                super.visit(that);
                needsParens = onp;
            }
            
            shared actual void visit(Tree.QualifiedMemberOrTypeExpression that) {
                value onp = needsParens;
                needsParens = true;
                super.visit(that);
                needsParens = onp;
            }
            
            shared actual void visit(Tree.StatementOrArgument that) {
                value onp = needsParens;
                needsParens = false;
                super.visit(that);
                needsParens = onp;
            }
            
            shared actual void visit(Tree.Expression that) {
                value onp = needsParens;
                needsParens = false;
                super.visit(that);
                needsParens = onp;
            }
        }.visit(rootNode);
    }

    void inlineAliasDefinitionReference(JList<CommonToken> tokens, 
        JList<CommonToken> declarationTokens, Node reference, 
        StringBuilder result, Tree.BaseType baseType) {
        
        if (exists t = baseType.typeModel,
            is TypeParameter td = t.declaration,
            is Generic ta = editorData.declaration) {
            
            value index = ta.typeParameters.indexOf(td);
            if (index >= 0) {
                switch (reference)
                case (is Tree.SimpleType) {
                    value types = reference.typeArgumentList.types;
                    if (types.size() > index, 
                        exists type = types[index]) {
                        result.append(nodes.text(type, tokens));
                        return; //EARLY EXIT!
                    }
                }
                case (is Tree.StaticMemberOrTypeExpression) {
                    value tas = reference.typeArguments;
                    if (is Tree.TypeArgumentList tas) {
                        value types = tas.types;
                        if (types.size() > index, 
                            exists type = types[index]) {
                            result.append(nodes.text(type, tokens));
                            return;  //EARLY EXIT!
                        }
                    } else {
                        value types = tas.typeModels;
                        if (types.size() > index, 
                            exists type = types[index]) {
                            result.append(type.asSourceCodeString(baseType.unit));
                            return; //EARLY EXIT!
                        }
                    }
                }
                else {}
            }
        }
        
        result.append(baseType.identifier.text);
    }

    void inlineDefinitionReference(
        JList<CommonToken> tokens, 
        JList<CommonToken> declarationTokens, 
        Node reference, 
        Tree.InvocationExpression? invocation, 
        Tree.BaseMemberExpression|Tree.This localReference, 
        StringBuilder result) {
        
        if (is Tree.This localReference) {
            if (is Tree.QualifiedMemberOrTypeExpression reference) {
                result.append(nodes.text(reference.primary, tokens));
                return;
            }
        }
        else {
            if (exists invocation,
                is FunctionOrValue dec = localReference.declaration,
                dec.parameter) {
    
                value param = dec.initializerParameter;
                if (param.declaration == editorData.declaration) {
                    if (invocation.positionalArgumentList exists) {
                        interpolatePositionalArguments {
                            result = result;
                            invocation = invocation;
                            reference = localReference;
                            sequenced = param.sequenced;
                            tokens = tokens;
                        };
                    }
                    if (invocation.namedArgumentList exists) {
                        interpolateNamedArguments {
                            result = result;
                            invocation = invocation;
                            reference = localReference;
                            sequenced = param.sequenced;
                            tokens = tokens;
                        };
                    }
                    return; //NOTE: early exit!
                }
            }
            
            if (is Tree.QualifiedMemberOrTypeExpression reference, 
                localReference.declaration.classOrInterfaceMember) {
                //assume it's a reference to the immediately 
                //containing class, i.e. the receiver
                //TODO: handle refs to outer classes
                result.append(nodes.text(reference.primary, tokens))
                    .append(".");
            }
        }
        
        result.append(nodes.text(localReference, declarationTokens));
    }

    void inlineDefinition(
        JList<CommonToken> tokens, 
        JList<CommonToken> declarationTokens, 
        Node definition, 
        TextChange tfc,
        Tree.InvocationExpression? invocation, 
        Tree.MemberOrTypeExpression|Tree.SimpleType reference, 
        Boolean needsParens) {
        
        value dec = switch (reference)
            case (is Tree.MemberOrTypeExpression) 
                reference.declaration
            case (is Tree.SimpleType) 
                reference.declarationModel;
        
        if (inlineRef(reference, dec)) {
            //TODO: breaks for invocations like f(f(x, y),z)
            value result = StringBuilder();

            class InterpolationVisitor() extends Visitor() {
                variable Integer start = 0;
                value template = nodes.text(definition, declarationTokens);
                value templateStart = definition.startIndex.intValue();
                void appendUpTo(Node it) {
                    value text = template[start:
                        it.startIndex.intValue() - templateStart - start];
                    result.append(text);
                    start = it.endIndex.intValue() - templateStart;
                }
                
                shared actual void visit(Tree.QualifiedMemberOrTypeExpression it) {
                    //visit the primary first!
                    if (exists p = it.primary) {
                        p.visit(this);
                    }
                }
                
                shared actual void visit(Tree.This it) {
                    appendUpTo(it);
                    inlineDefinitionReference {
                        tokens = tokens;
                        declarationTokens = declarationTokens;
                        reference = reference;
                        invocation = invocation;
                        result = result;
                        localReference = it;
                    };
                    super.visit(it);
                }
                
                shared actual void visit(Tree.BaseMemberExpression it) {
                    appendUpTo(it.identifier);
                    inlineDefinitionReference {
                        tokens = tokens;
                        declarationTokens = declarationTokens;
                        reference = reference;
                        invocation = invocation;
                        result = result;
                        localReference = it;
                    };
                    super.visit(it);
                }
                
                shared actual void visit(Tree.QualifiedType it) {
                    //visit the qualifying type before 
                    //visiting the type argument list
                    if (exists ot = it.outerType) {
                        ot.visit(this);
                    }
                    if (exists tal = it.typeArgumentList) {
                        tal.visit(this);
                    }
                }
                
                shared actual void visit(Tree.BaseType it) {
                    appendUpTo(it.identifier);
                    inlineAliasDefinitionReference {
                        tokens = tokens;
                        declarationTokens = declarationTokens;
                        reference = reference;
                        result = result;
                        baseType = it;
                    };
                    super.visit(it);
                }
                
                shared void finish() {
                    value text = template[start:template.size-start];
                    result.append(text);
                }
            }
            
            value iv = InterpolationVisitor();
            definition.visit(iv);
            iv.finish();
            
            if (needsParens &&
                (definition is 
                    Tree.OperatorExpression
                  | Tree.IfExpression
                  | Tree.SwitchExpression
                  | Tree.ObjectExpression
                  | Tree.LetExpression
                  | Tree.FunctionArgument)) {
                result.insert(0, "(").append(")");
            }
            
            value node = invocation else reference;
            
            addEditToChange(tfc, 
                newReplaceEdit {
                    start = node.startIndex.intValue();
                    length = node.distance.intValue();
                    text = result.string;
                });
        }
    }

    Boolean inlineRef(Node that, Declaration dec)
            => (!editorData.justOne
              || that.unit == editorData.node.unit
                 && that.startIndex exists
                 && that.startIndex == editorData.node.startIndex)
            && original(dec) == editorData.declaration;

    void interpolatePositionalArguments(StringBuilder result, 
        Tree.InvocationExpression invocation, 
        Tree.StaticMemberOrTypeExpression reference, 
        Boolean sequenced, JList<CommonToken> tokens) {
        
        variable Boolean first = true;
        variable Boolean found = false;
        
        if (sequenced) {
            result.append("{");
        }
        
        value args = invocation.positionalArgumentList.positionalArguments;
        for (arg in args) {
            value param = arg.parameter;
            if (reference.declaration == param.model) {
                if (param.sequenced &&
                    arg is Tree.ListedArgument) {
                    if (first) {
                        result.append(" ");
                    }
                    
                    if (!first) {
                        result.append(", ");
                    }
                    
                    first = false;
                }
                
                result.append(nodes.text(arg, tokens));
                found = true;
            }
        }
        
        if (sequenced) {
            if (!first) {
                result.append(" ");
            }
            
            result.append("}");
        }
        
        if (!found) {
            //TODO: use default value!
        }
    }

    void interpolateNamedArguments(StringBuilder result, 
        Tree.InvocationExpression invocation, 
        Tree.StaticMemberOrTypeExpression reference,
        Boolean sequenced, 
        JList<CommonToken> tokens) {
        
        variable Boolean found = false;
        value args = invocation.namedArgumentList.namedArguments;
        for (arg in args) {
            if (reference.declaration == arg.parameter.model) {
                assert (is Tree.SpecifiedArgument sa = arg);
                value argTerm = sa.specifierExpression.expression.term;
                result//.append(template.substring(start,it.getStartIndex()-templateStart))
                    .append(nodes.text(argTerm, tokens));
                //start = it.getStopIndex()-templateStart+1;
                found = true;
            }
        }
        
        if (exists seqArg = invocation.namedArgumentList.sequencedArgument, 
            reference.declaration == seqArg.parameter.model) {
            result//.append(template.substring(start,it.getStartIndex()-templateStart))
                .append("{");
            //start = it.getStopIndex()-templateStart+1;;
            
            variable Boolean first = true;
            value pargs = seqArg.positionalArguments;
            
            for (pa in pargs) {
                if (first) {
                    result.append(" ");
                }
                
                if (!first) {
                    result.append(", ");
                }
                
                first = false;
                result.append(nodes.text(pa, tokens));
            }
            
            if (!first) {
                result.append(" ");
            }
            
            result.append("}");
            found = true;
        }
        
        if (!found) {
            if (sequenced) {
                result.append("{}");
            } else {
                //TODO: use default value!
            }
        }
    }
}
