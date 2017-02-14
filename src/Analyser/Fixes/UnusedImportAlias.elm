module Analyser.Fixes.UnusedImportAlias exposing (fix)

import Analyser.Messages.Types exposing (MessageData(UnusedImportAlias))
import AST.Types exposing (ModuleName, File, Import, Exposure, ValueConstructorExpose, Expose, ExposedType)
import AST.Ranges as Ranges exposing (Range)
import AST.Imports


fix : List ( String, String, File ) -> MessageData -> List ( String, String )
fix input messageData =
    case messageData of
        UnusedImportAlias fileName moduleName range ->
            case List.head input of
                Nothing ->
                    []

                Just triple ->
                    updateImport triple moduleName range

        _ ->
            []


updateImport : ( String, String, File ) -> ModuleName -> Range -> List ( String, String )
updateImport ( fileName, content, ast ) moduleName range =
    let
        maybeImport =
            findImport ast range
    in
        case maybeImport of
            Just imp ->
                [ ( fileName
                  , writeNewImport imp.range { imp | moduleAlias = Nothing } content
                  )
                ]

            Nothing ->
                []


writeNewImport : Range -> Import -> String -> String
writeNewImport r imp i =
    replaceLines
        ( r.start.row, r.end.row )
        (AST.Imports.naiveStringifyImport imp)
        i


replaceLines : ( Int, Int ) -> String -> String -> String
replaceLines ( start, end ) fix input =
    let
        lines =
            String.split "\n" input
    in
        String.join "\n" <|
            List.concat
                [ List.take start lines
                , [ fix ]
                , List.drop end lines
                ]


findImport : File -> Range -> Maybe Import
findImport ast range =
    ast.imports
        |> List.filter (.range >> Ranges.containsRange range)
        |> List.head