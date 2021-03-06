module ASTUtil.Inspector exposing (Config, Order(Continue, Inner, Post, Pre, Skip), defaultConfig, inspect)

import Elm.Syntax.Declaration exposing (..)
import Elm.Syntax.Expression exposing (..)
import Elm.Syntax.File exposing (File)
import Elm.Syntax.Infix exposing (..)
import Elm.Syntax.Module exposing (..)
import Elm.Syntax.Pattern exposing (..)
import Elm.Syntax.Type exposing (..)
import Elm.Syntax.TypeAlias exposing (..)
import Elm.Syntax.TypeAnnotation exposing (..)


type Order context x
    = Skip
    | Continue
    | Pre (x -> context -> context)
    | Post (x -> context -> context)
    | Inner ((context -> context) -> x -> context -> context)


type alias Config context =
    { onFile : Order context File
    , onImport : Order context Import
    , onFunction : Order context Function
    , onFunctionSignature : Order context FunctionSignature
    , onPortDeclaration : Order context FunctionSignature
    , onTypeAlias : Order context TypeAlias
    , onDestructuring : Order context ( Pattern, Expression )
    , onExpression : Order context Expression
    , onOperatorApplication : Order context ( String, InfixDirection, Expression, Expression )
    , onTypeAnnotation : Order context TypeAnnotation
    , onLambda : Order context Lambda
    , onLetBlock : Order context LetBlock
    , onCase : Order context Case
    , onFunctionOrValue : Order context String
    , onPrefixOperator : Order context String
    , onRecordAccess : Order context ( Expression, String )
    , onRecordUpdate : Order context RecordUpdate
    }


defaultConfig : Config x
defaultConfig =
    { onFile = Continue
    , onImport = Continue
    , onFunction = Continue
    , onPortDeclaration = Continue
    , onFunctionSignature = Continue
    , onTypeAnnotation = Continue
    , onTypeAlias = Continue
    , onDestructuring = Continue
    , onExpression = Continue
    , onLambda = Continue
    , onOperatorApplication = Continue
    , onLetBlock = Continue
    , onCase = Continue
    , onFunctionOrValue = Continue
    , onPrefixOperator = Continue
    , onRecordAccess = Continue
    , onRecordUpdate = Continue
    }


actionLambda : Order config x -> (config -> config) -> x -> config -> config
actionLambda act =
    case act of
        Skip ->
            \_ _ c -> c

        Continue ->
            \f _ c -> f c

        Pre g ->
            \f x c -> g x c |> f

        Post g ->
            \f x c -> f c |> g x

        Inner g ->
            \f x c -> g f x c


inspect : Config a -> File -> a -> a
inspect config file context =
    actionLambda config.onFile
        (inspectImports config file.imports >> inspectDeclarations config file.declarations)
        file
        context


inspectImports : Config context -> List Import -> context -> context
inspectImports config imports context =
    List.foldl (inspectImport config) context imports


inspectImport : Config context -> Import -> context -> context
inspectImport config imp context =
    actionLambda config.onImport
        identity
        imp
        context


inspectDeclarations : Config context -> List Declaration -> context -> context
inspectDeclarations config declarations context =
    List.foldl (inspectDeclaration config) context declarations


inspectLetDeclarations : Config context -> List LetDeclaration -> context -> context
inspectLetDeclarations config declarations context =
    List.foldl (inspectLetDeclaration config) context declarations


inspectLetDeclaration : Config context -> LetDeclaration -> context -> context
inspectLetDeclaration config declaration context =
    case declaration of
        LetFunction function ->
            inspectFunction config function context

        LetDestructuring pattern expression ->
            inspectDestructuring config ( pattern, expression ) context


inspectDeclaration : Config context -> Declaration -> context -> context
inspectDeclaration config declaration context =
    case declaration of
        FuncDecl function ->
            inspectFunction config function context

        AliasDecl typeAlias ->
            inspectTypeAlias config typeAlias context

        TypeDecl typeDecl ->
            inspectType config typeDecl context

        PortDeclaration signature ->
            inspectPortDeclaration config signature context

        InfixDeclaration _ ->
            context

        Destructuring pattern expresion ->
            inspectDestructuring config ( pattern, expresion ) context


inspectType : Config context -> Type -> context -> context
inspectType config typeDecl context =
    List.foldl (inspectValueConstructor config) context typeDecl.constructors


inspectValueConstructor : Config context -> ValueConstructor -> context -> context
inspectValueConstructor config valueConstructor context =
    List.foldl (inspectTypeAnnotation config) context valueConstructor.arguments


inspectTypeAlias : Config context -> TypeAlias -> context -> context
inspectTypeAlias config typeAlias context =
    actionLambda
        config.onTypeAlias
        (inspectTypeAnnotation config typeAlias.typeAnnotation)
        typeAlias
        context


inspectDestructuring : Config context -> ( Pattern, Expression ) -> context -> context
inspectDestructuring config destructuring context =
    actionLambda
        config.onDestructuring
        (inspectExpression config (Tuple.second destructuring))
        destructuring
        context


inspectFunction : Config context -> Function -> context -> context
inspectFunction config function context =
    actionLambda
        config.onFunction
        (inspectExpression config function.declaration.expression
            >> (Maybe.withDefault identity <|
                    Maybe.map (inspectSignature config) function.signature
               )
        )
        function
        context


inspectPortDeclaration : Config context -> FunctionSignature -> context -> context
inspectPortDeclaration config signature context =
    actionLambda
        config.onPortDeclaration
        (inspectSignature config signature)
        signature
        context


inspectSignature : Config context -> FunctionSignature -> context -> context
inspectSignature config signature context =
    actionLambda
        config.onFunctionSignature
        (inspectTypeAnnotation config signature.typeAnnotation)
        signature
        context


inspectTypeAnnotation : Config context -> TypeAnnotation -> context -> context
inspectTypeAnnotation config typeAnnotation context =
    actionLambda
        config.onTypeAnnotation
        (inspectTypeAnnotationInner config typeAnnotation)
        typeAnnotation
        context


inspectTypeAnnotationInner : Config context -> TypeAnnotation -> context -> context
inspectTypeAnnotationInner config typeRefence context =
    case typeRefence of
        Typed _ _ typeArgs _ ->
            List.foldl (inspectTypeAnnotation config) context typeArgs

        Tupled typeAnnotations _ ->
            List.foldl (inspectTypeAnnotation config) context typeAnnotations

        Record recordDefinition _ ->
            List.foldl (inspectTypeAnnotation config) context (List.map Tuple.second recordDefinition)

        GenericRecord _ recordDefinition _ ->
            List.foldl (inspectTypeAnnotation config) context (List.map Tuple.second recordDefinition)

        FunctionTypeAnnotation left right _ ->
            List.foldl (inspectTypeAnnotation config) context [ left, right ]

        Unit _ ->
            context

        GenericType _ _ ->
            context


inspectExpression : Config context -> Expression -> context -> context
inspectExpression config expression context =
    actionLambda
        config.onExpression
        (inspectInnerExpression config <| Tuple.second expression)
        expression
        context


inspectInnerExpression : Config context -> InnerExpression -> context -> context
inspectInnerExpression config expression context =
    case expression of
        UnitExpr ->
            context

        FunctionOrValue functionOrVal ->
            actionLambda config.onFunctionOrValue
                identity
                functionOrVal
                context

        PrefixOperator prefix ->
            actionLambda config.onPrefixOperator
                identity
                prefix
                context

        Operator _ ->
            context

        Integer _ ->
            context

        Floatable _ ->
            context

        Negation x ->
            inspectExpression config x context

        Literal _ ->
            context

        CharLiteral _ ->
            context

        QualifiedExpr _ _ ->
            context

        RecordAccess ex1 key ->
            actionLambda config.onRecordAccess
                (inspectExpression config ex1)
                ( ex1, key )
                context

        RecordAccessFunction _ ->
            context

        GLSLExpression _ ->
            context

        Application expressionList ->
            List.foldl (inspectExpression config) context expressionList

        OperatorApplication op dir left right ->
            actionLambda config.onOperatorApplication
                (flip (List.foldl (inspectExpression config)) [ left, right ])
                ( op, dir, left, right )
                context

        IfBlock e1 e2 e3 ->
            List.foldl (inspectExpression config) context [ e1, e2, e3 ]

        TupledExpression expressionList ->
            List.foldl (inspectExpression config) context expressionList

        ParenthesizedExpression inner ->
            inspectExpression config inner context

        LetExpression letBlock ->
            let
                next =
                    inspectLetDeclarations config letBlock.declarations >> inspectExpression config letBlock.expression
            in
            actionLambda config.onLetBlock
                next
                letBlock
                context

        CaseExpression caseBlock ->
            let
                context2 =
                    inspectExpression config caseBlock.expression context

                context3 =
                    List.foldl (\a b -> inspectCase config a b) context2 caseBlock.cases
            in
            context3

        LambdaExpression lambda ->
            actionLambda config.onLambda
                (inspectExpression config lambda.expression)
                lambda
                context

        ListExpr expressionList ->
            List.foldl (inspectExpression config) context expressionList

        RecordExpr expressionStringList ->
            List.foldl (\a b -> inspectExpression config (Tuple.second a) b) context expressionStringList

        RecordUpdateExpression recordUpdate ->
            actionLambda config.onRecordUpdate
                (\c -> List.foldl (\a b -> inspectExpression config (Tuple.second a) b) c recordUpdate.updates)
                recordUpdate
                context


inspectCase : Config context -> Case -> context -> context
inspectCase config caze context =
    actionLambda config.onCase
        (inspectExpression config (Tuple.second caze))
        caze
        context
