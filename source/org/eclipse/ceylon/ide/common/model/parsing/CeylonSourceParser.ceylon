/********************************************************************************
 * Copyright (c) 2011-2017 Red Hat Inc. and/or its affiliates and others
 *
 * This program and the accompanying materials are made available under the 
 * terms of the Apache License, Version 2.0 which is available at
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0 
 ********************************************************************************/
import org.eclipse.ceylon.compiler.typechecker {
    TypeChecker
}
import org.eclipse.ceylon.compiler.typechecker.context {
    PhasedUnit
}
import org.eclipse.ceylon.compiler.typechecker.parser {
    CeylonLexer,
    CeylonParser,
    CeylonInterpolatingLexer
}
import org.eclipse.ceylon.compiler.typechecker.tree {
    Tree
}
import org.eclipse.ceylon.compiler.typechecker.util {
    NewlineFixingStringStream
}
import org.eclipse.ceylon.ide.common.model {
    ModelAliases
}
import org.eclipse.ceylon.ide.common.typechecker {
    ProjectPhasedUnit,
    TypecheckerAliases
}
import org.eclipse.ceylon.ide.common.util {
    unsafeCast
}
import org.eclipse.ceylon.ide.common.vfs {
    BaseFileVirtualFile,
    BaseFolderVirtualFile,
    VfsAliases
}
import org.eclipse.ceylon.model.typechecker.model {
    Package
}
import org.eclipse.ceylon.model.typechecker.util {
    ModuleManager
}

import java.io {
    Reader,
    InputStreamReader
}
import java.util {
    List
}

import org.antlr.runtime {
    ANTLRStringStream,
    CommonTokenStream,
    CommonToken
}
import org.eclipse.ceylon.ide.common.platform {
    platformServices
}

shared class ParseResult(
    shared Tree.CompilationUnit compilationUnit,
    shared List<CommonToken> tokens) {
}

shared interface SourceCodeParser {
    
    function buildLexer(ANTLRStringStream stringStream) => 
            if (exists custom = platformServices.parser().buildCustomizedLexer)
    then custom(stringStream)
    else CeylonLexer(stringStream);
    
    function buildTokenStream(CeylonLexer lexer) => 
            if (exists custom = platformServices.parser().buildCustomizedTokenStream)
    then custom(CeylonInterpolatingLexer(lexer))
    else CommonTokenStream(CeylonInterpolatingLexer(lexer));
    
    function buildParser(CommonTokenStream tokenStream) => 
            if (exists custom = platformServices.parser().buildCustomizedParser)
    then custom(tokenStream)
    else CeylonParser(tokenStream);
    
    function getTokens(CeylonLexer lexer, CommonTokenStream tokenStream) =>
            if (exists custom = platformServices.parser().buildCustomizedTokens)
    then custom(lexer, tokenStream)
    else unsafeCast<List<CommonToken>>(tokenStream.tokens);
    
    shared ParseResult parseSourceCode(
        Reader sourceCode) {
        value input = NewlineFixingStringStream.fromReader(sourceCode);

        value lexer = buildLexer(input);
        value tokenStream = buildTokenStream(lexer);

        value parser = buildParser(tokenStream);
        value cu = parser.compilationUnit();

        value lexerErrors = lexer.errors;
        for (le in lexerErrors) {
            cu.addLexError(le);
        }
        lexerErrors.clear();
        
        value parserErrors = parser.errors;
        for (pe in parserErrors) {
            cu.addParseError(pe);
        }
        parserErrors.clear();
        
        value tokens = getTokens(lexer, tokenStream);
        return ParseResult(cu, tokens);
    }
}

shared object sourceCodeParser satisfies SourceCodeParser {
}

shared interface CeylonSourceParser<ResultPhasedUnit>
        satisfies SourceCodeParser
        given ResultPhasedUnit satisfies PhasedUnit {

    shared ResultPhasedUnit parseSourceCodeToPhasedUnit(
        ModuleManager moduleManager,
        Reader sourceCode,
        Package pkg) =>
            let (parseResult = parseSourceCode(sourceCode)) 
            createPhasedUnit(parseResult.compilationUnit, pkg, parseResult.tokens);

    shared ResultPhasedUnit parseFileToPhasedUnit(
        ModuleManager moduleManager,
        TypeChecker typeChecker,
        BaseFileVirtualFile file,
        BaseFolderVirtualFile srcDir,
        Package pkg)
            => parseSourceCodeToPhasedUnit(moduleManager,
            InputStreamReader(file.inputStream, charset(file)),
            pkg);

    shared formal ResultPhasedUnit createPhasedUnit(Tree.CompilationUnit cu, Package pkg, List<CommonToken> tokenStream);
    shared formal String charset(BaseFileVirtualFile file);
}

shared class ProjectSourceParser<NativeProject, NativeResource, NativeFolder, NativeFile>(
    ceylonProject,
    unitFile,
    srcDir)
        satisfies CeylonSourceParser<ProjectPhasedUnit<NativeProject, NativeResource, NativeFolder, NativeFile>>
                & ModelAliases<NativeProject, NativeResource, NativeFolder, NativeFile>
                & TypecheckerAliases<NativeProject, NativeResource, NativeFolder, NativeFile>
                & VfsAliases<NativeProject,NativeResource, NativeFolder, NativeFile>

        given NativeProject satisfies Object
        given NativeResource satisfies Object
        given NativeFolder satisfies NativeResource
        given NativeFile satisfies NativeResource {
    shared CeylonProjectAlias ceylonProject;
    shared FileVirtualFileAlias unitFile;
    shared FolderVirtualFileAlias srcDir;
    assert(exists modules=ceylonProject.modules);
    
    shared actual default ProjectPhasedUnitAlias createPhasedUnit(
        Tree.CompilationUnit cu,
        Package pkg,
        List<CommonToken> tokens)
        => ProjectPhasedUnit<NativeProject, NativeResource, NativeFolder, NativeFile>(ceylonProject, unitFile, srcDir, cu, pkg,
            modules.manager,
            modules.sourceMapper,
            modules.manager.typeChecker,
            tokens);

    shared actual default String charset(BaseFileVirtualFile file)
        => ceylonProject.defaultCharset;
}
