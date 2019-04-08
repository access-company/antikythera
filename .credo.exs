# Copyright(c) 2015-2019 ACCESS CO., LTD. All rights reserved.

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "web/", "core/", "local/", "test/"],
        excluded: []
      },
      checks: [
        {Credo.Check.Consistency.ExceptionNames},
        {Credo.Check.Consistency.LineEndings},
        {Credo.Check.Consistency.MultiAliasImportRequireUse, false},
        {Credo.Check.Consistency.ParameterPatternMatching},
        {Credo.Check.Consistency.SpaceAroundOperators},
        {Credo.Check.Consistency.SpaceInParentheses, false},
        {Credo.Check.Consistency.TabsOrSpaces},

        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Design.DuplicatedCode},
        {Credo.Check.Design.TagFIXME},
        {Credo.Check.Design.TagTODO},

        {Credo.Check.Readability.AliasOrder, false},
        {Credo.Check.Readability.FunctionNames},
        {Credo.Check.Readability.LargeNumbers},
        {Credo.Check.Readability.MaxLineLength, max_length: 140},
        {Credo.Check.Readability.ModuleAttributeNames},
        {Credo.Check.Readability.ModuleDoc, false},
        {Credo.Check.Readability.ModuleNames},
        {Credo.Check.Readability.ParenthesesInCondition},
        {Credo.Check.Readability.ParenthesesOnZeroArityDefs, false},
        {Credo.Check.Readability.PredicateFunctionNames},
        {Credo.Check.Readability.PreferImplicitTry, false},
        {Credo.Check.Readability.RedundantBlankLines},
        {Credo.Check.Readability.SinglePipe, false},
        {Credo.Check.Readability.SpaceAfterCommas},
        {Credo.Check.Readability.Specs, false},
        {Credo.Check.Readability.StringSigils},
        {Credo.Check.Readability.TrailingBlankLine},
        {Credo.Check.Readability.TrailingWhiteSpace},
        {Credo.Check.Readability.UnnecessaryAliasExpansion},
        {Credo.Check.Readability.VariableNames},

        {Credo.Check.Refactor.ABCSize},
        {Credo.Check.Refactor.AppendSingleItem},
        {Credo.Check.Refactor.CondStatements},
        {Credo.Check.Refactor.CyclomaticComplexity},
        {Credo.Check.Refactor.DoubleBooleanNegation},
        {Credo.Check.Refactor.FunctionArity, max_arity: 8},
        {Credo.Check.Refactor.LongQuoteBlocks},
        {Credo.Check.Refactor.MapInto},
        {Credo.Check.Refactor.MatchInCondition},
        {Credo.Check.Refactor.ModuleDependencies, false},
        {Credo.Check.Refactor.NegatedConditionsInUnless},
        {Credo.Check.Refactor.NegatedConditionsWithElse},
        {Credo.Check.Refactor.Nesting},
        {Credo.Check.Refactor.PerceivedComplexity},
        {Credo.Check.Refactor.PipeChainStart, false},
        {Credo.Check.Refactor.UnlessWithElse},
        {Credo.Check.Refactor.VariableRebinding},

        {Credo.Check.Warning.BoolOperationOnSameValues},
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck},
        {Credo.Check.Warning.IExPry},
        {Credo.Check.Warning.IoInspect},
        {Credo.Check.Warning.MapGetUnsafePass},
        {Credo.Check.Warning.OperationOnSameValues},
        {Credo.Check.Warning.OperationWithConstantResult},
        {Credo.Check.Warning.RaiseInsideRescue},
        {Credo.Check.Warning.UnsafeToAtom},
        {Credo.Check.Warning.UnusedEnumOperation},
        {Credo.Check.Warning.UnusedFileOperation},
        {Credo.Check.Warning.UnusedKeywordOperation},
        {Credo.Check.Warning.UnusedListOperation},
        {Credo.Check.Warning.UnusedPathOperation},
        {Credo.Check.Warning.UnusedRegexOperation},
        {Credo.Check.Warning.UnusedStringOperation},
        {Credo.Check.Warning.UnusedTupleOperation},
      ]
    }
  ]
}
