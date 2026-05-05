module Backend exposing (..)

import Array exposing (Array)
import Basics.Extra exposing (flip)
import Codecs
import Dict exposing (Dict)
import Env
import Html
import Lamdera exposing (ClientId, SessionId)
import Maybe.Extra as Maybe
import Set exposing (Set)
import Types exposing (..)


type alias Model =
    BackendModel


type alias PendingTransaction =
    -- This represents the fields of a Transaction + its date
    { spendingId : SpendingId
    , year : Int
    , month : Int
    , day : Int
    , secondaryDescription : String
    , group : String
    , amount : Amount ()
    , side : TransactionSide
    , groupMembersKey : String
    , groupMembers : Set String
    , status : TransactionStatus
    }


app =
    Lamdera.backend
        { init = init
        , update = update
        , updateFromFrontend = updateFromFrontend
        , subscriptions = \m -> Sub.none
        }


init : ( Model, Cmd BackendMsg )
init =
    ( { years = Dict.empty
      , spendings = Array.empty
      , groups = Dict.empty
      , totalGroupCredits = Dict.empty
      , persons = Dict.empty
      , nextPersonId = 0
      , loggedInSessions = Set.empty
      }
    , Cmd.none
    )


update : BackendMsg -> Model -> ( Model, Cmd BackendMsg )
update msg model =
    case msg of
        NoOpBackendMsg ->
            ( model, Cmd.none )


updateFromFrontend : SessionId -> ClientId -> ToBackend -> Model -> ( Model, Cmd BackendMsg )
updateFromFrontend sessionId clientId msg model =
    case ( Set.member sessionId model.loggedInSessions, msg ) of
        ( _, CheckPassword password ) ->
            if password == Env.password then
                ( { model | loggedInSessions = Set.insert sessionId model.loggedInSessions }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model, Cmd.none )

        ( _, CheckAuthentication ) ->
            ( model
            , Lamdera.sendToFrontend clientId
                (AuthenticationStatus (Set.member sessionId model.loggedInSessions))
            )

        ( False, _ ) ->
            ( model, Cmd.none )

        ( True, NoOpToBackend ) ->
            ( model, Cmd.none )

        ( True, CheckValidName name ) ->
            ( model
            , if checkValidName model name then
                Cmd.none

              else
                Lamdera.sendToFrontend clientId (NameAlreadyExists name)
            )

        ( True, CreatePerson person ) ->
            if checkValidName model person then
                ( { model
                    | persons =
                        Dict.insert person
                            { id = model.nextPersonId
                            , belongsTo = Set.empty
                            }
                            model.persons
                    , nextPersonId = model.nextPersonId + 1
                  }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model
                , Lamdera.sendToFrontend clientId (NameAlreadyExists person)
                )

        ( True, CreateGroup name members ) ->
            if checkValidName model name then
                ( { model | groups = Dict.insert name members model.groups }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model
                , Lamdera.sendToFrontend clientId (NameAlreadyExists name)
                )

        ( True, CreateSpending { description, total, transactions } ) ->
            case validateSpendingTransactions total transactions of
                Err errorMessage ->
                    ( model, Lamdera.sendToFrontend clientId (SpendingError errorMessage) )

                Ok normalizedTransactions ->
                    ( createSpendingInModel description total normalizedTransactions model
                    , Lamdera.sendToFrontend clientId OperationSuccessful
                    )

        ( True, EditSpending { spendingId, description, total, transactions } ) ->
            -- First, validate that the spending exists and is active
            case Array.get spendingId model.spendings of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending not found") )

                Just spending ->
                    if spending.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending is already deleted or replaced") )

                    else
                        -- Valid edit: delete old, add new
                        case validateSpendingTransactions total transactions of
                            Err errorMessage ->
                                ( model, Lamdera.sendToFrontend clientId (SpendingError errorMessage) )

                            Ok normalizedTransactions ->
                                let
                                    activeTransactions =
                                        getSpendingTransactionsWithIds spendingId model

                                    cleanedModel =
                                        List.foldl
                                            removeTransactionFromModel
                                            (model
                                                |> setSpendingStatus spendingId Replaced
                                                |> setTransactionStatuses spendingId Replaced
                                            )
                                            activeTransactions
                                in
                                ( createSpendingInModel description total normalizedTransactions cleanedModel
                                , Lamdera.sendToFrontend clientId OperationSuccessful
                                )

        ( True, DeleteSpending spendingId ) ->
            -- First, validate that the spending exists and is active
            case Array.get spendingId model.spendings of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending not found") )

                Just spending ->
                    if spending.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending is already deleted or replaced") )

                    else
                        -- Valid delete: mark as deleted and remove from totals
                        let
                            activeTransactions =
                                getSpendingTransactionsWithIds spendingId model

                            finalModel =
                                List.foldl
                                    removeTransactionFromModel
                                    (model
                                        |> setSpendingStatus spendingId Deleted
                                        |> setTransactionStatuses spendingId Deleted
                                    )
                                    activeTransactions
                        in
                        ( finalModel, Lamdera.sendToFrontend clientId OperationSuccessful )

        ( True, AutocompletePerson prefix ) ->
            ( model
            , Dict.keys model.persons
                |> autocomplete clientId prefix AutocompletePersonPrefix InvalidPersonPrefix
            )

        ( True, AutocompleteGroup prefix ) ->
            ( model
            , Dict.keys model.groups
                -- persons are automatically single-member groups
                |> (++) (Dict.keys model.persons)
                |> autocomplete clientId prefix AutocompleteGroupPrefix InvalidGroupPrefix
            )

        ( True, RequestSpendingDetails spendingId ) ->
            case Array.get spendingId model.spendings of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending not found") )

                Just spending ->
                    if spending.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending is not active") )

                    else
                        let
                            spendingTransactions =
                                spendingTransactionsForDetails spendingId model
                        in
                        case spendingTransactions of
                            [] ->
                                ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending has no active transactions") )

                            _ ->
                                ( model
                                , Lamdera.sendToFrontend clientId
                                    (SpendingDetails
                                        { spendingId = spendingId
                                        , description = spending.description
                                        , total = spending.total
                                        , transactions = spendingTransactions
                                        }
                                    )
                                )

        ( True, RequestUserGroups user ) ->
            case Dict.get user model.persons of
                Nothing ->
                    ( model
                    , Cmd.none
                    )

                Just person ->
                    let
                        groupsWithAmounts =
                            person.belongsTo
                                |> Set.toList
                                |> List.foldl
                                    (\key totalGroupCredits ->
                                        Dict.get key model.totalGroupCredits
                                            |> Maybe.withDefault Dict.empty
                                            |> addAmounts totalGroupCredits
                                    )
                                    Dict.empty
                                |> Dict.toList

                        debitorsWithAmounts =
                            groupsWithAmounts
                                |> List.filter (\( _, Amount credit ) -> credit < 0)
                                |> List.map
                                    (\( group, Amount debit ) ->
                                        ( group
                                        , getGroupMembers model group
                                        , Amount -debit
                                        )
                                    )

                        creditorsWithAmounts =
                            groupsWithAmounts
                                |> List.filter (\( _, Amount credit ) -> credit > 0)
                                |> List.map
                                    (\( group, credit ) ->
                                        ( group
                                        , getGroupMembers model group
                                        , credit
                                        )
                                    )
                    in
                    ( model
                    , Lamdera.sendToFrontend clientId
                        (ListUserGroups
                            { user = user
                            , debitors = debitorsWithAmounts
                            , creditors = creditorsWithAmounts
                            }
                        )
                    )

        ( True, RequestGroupTransactions group ) ->
            let
                transactions =
                    allTransactionsWithIds model
                        |> List.filterMap (groupTransactionForList model group)
            in
            ( model
            , Lamdera.sendToFrontend clientId
                (ListGroupTransactions
                    { group = group
                    , transactions = transactions
                    }
                )
            )

        ( True, RequestAllTransactions ) ->
            ( model
            , model
                |> Codecs.encodeToString
                |> JsonExport
                |> Lamdera.sendToFrontend clientId
            )

        ( True, ImportJson json ) ->
            case Codecs.decodeString json of
                Ok newModel ->
                    ( newModel
                    , Lamdera.sendToFrontend clientId OperationSuccessful
                    )

                Err _ ->
                    ( model
                    , Lamdera.sendToFrontend clientId (SpendingError "Import failed: the JSON could not be decoded.")
                    )


getGroupMembers model group =
    case Dict.get group model.groups of
        Nothing ->
            -- persons are automatically single-member groups
            Dict.singleton group (Share 1)

        Just members ->
            members


autocomplete clientId prefix autocompleteMsg invalidPrefixMsg list =
    let
        prefixLower =
            String.toLower prefix

        matches =
            List.filter
                (String.toLower >> String.startsWith prefixLower)
                list
    in
    case matches of
        [] ->
            Lamdera.sendToFrontend clientId (invalidPrefixMsg prefix)

        [ name ] ->
            Lamdera.sendToFrontend clientId
                (autocompleteMsg
                    { prefixLower = prefixLower
                    , longestCommonPrefix = name
                    , complete = True
                    }
                )

        h :: _ ->
            let
                ( longestCommonPrefix, commonPrefixMatch ) =
                    longestPrefix 0 matches
            in
            if commonPrefixMatch then
                Lamdera.sendToFrontend clientId
                    (autocompleteMsg
                        { prefixLower = prefixLower
                        , longestCommonPrefix = String.left longestCommonPrefix h
                        , complete = True
                        }
                    )

            else if longestCommonPrefix > String.length prefixLower then
                Lamdera.sendToFrontend clientId
                    (autocompleteMsg
                        { prefixLower = prefixLower
                        , longestCommonPrefix = String.left longestCommonPrefix h
                        , complete = False
                        }
                    )

            else
                Cmd.none


longestPrefix acc strings =
    let
        ( heads, tails ) =
            List.map String.uncons strings
                |> Maybe.combine
                |> Maybe.withDefault []
                |> List.unzip
    in
    case List.map Char.toLower heads of
        [] ->
            ( acc, True )

        char :: chars ->
            if List.all ((==) char) chars then
                longestPrefix (acc + 1) tails

            else
                ( acc, False )


checkValidName : Model -> String -> Bool
checkValidName model name =
    String.length name
        > 0
        && not (Dict.member name model.persons)
        && not (Dict.member name model.groups)


addToTotalGroupCredits :
    String
    -> Dict String (Amount Credit)
    -> Dict String (Dict String (Amount Credit))
    -> Dict String (Dict String (Amount Credit))
addToTotalGroupCredits groupMembersKey groupCredits =
    Dict.update groupMembersKey
        (Maybe.map (addAmounts groupCredits >> Just)
            >> Maybe.withDefault (Just groupCredits)
        )


dayTransactionCount : Int -> Int -> Int -> Model -> Int
dayTransactionCount year month day model =
    Dict.get year model.years
        |> Maybe.andThen (.months >> Dict.get month)
        |> Maybe.andThen (.days >> Dict.get day)
        |> Maybe.map (.transactions >> Array.length)
        |> Maybe.withDefault 0


addTransactionToYear : PendingTransaction -> Dict String (Amount Credit) -> Maybe Year -> Year
addTransactionToYear transaction groupCredits maybeYear =
    case maybeYear of
        Nothing ->
            { months =
                Dict.singleton transaction.month
                    (addTransactionToMonth transaction groupCredits Nothing)
            , totalGroupCredits =
                Dict.singleton transaction.groupMembersKey groupCredits
            }

        Just year ->
            { months =
                year.months
                    |> Dict.update transaction.month (addTransactionToMonth transaction groupCredits >> Just)
            , totalGroupCredits =
                year.totalGroupCredits
                    |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
            }


addTransactionToMonth : PendingTransaction -> Dict String (Amount Credit) -> Maybe Month -> Month
addTransactionToMonth transaction groupCredits maybeMonth =
    case maybeMonth of
        Nothing ->
            { days =
                Dict.singleton transaction.day
                    (addTransactionToDay transaction groupCredits Nothing)
            , totalGroupCredits =
                Dict.singleton transaction.groupMembersKey groupCredits
            }

        Just month ->
            { days =
                month.days
                    |> Dict.update transaction.day (addTransactionToDay transaction groupCredits >> Just)
            , totalGroupCredits =
                month.totalGroupCredits
                    |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
            }


addTransactionToDay : PendingTransaction -> Dict String (Amount Credit) -> Maybe Day -> Day
addTransactionToDay transaction groupCredits maybeDay =
    case maybeDay of
        Nothing ->
            { transactions = Array.fromList [ storedTransaction transaction ]
            , totalGroupCredits =
                Dict.singleton transaction.groupMembersKey groupCredits
            }

        Just day ->
            { transactions = Array.push (storedTransaction transaction) day.transactions
            , totalGroupCredits =
                day.totalGroupCredits
                    |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
            }


removeTransactionFromYear : TransactionId -> Transaction -> Dict String (Amount Credit) -> Maybe Year -> Maybe Year
removeTransactionFromYear transactionId transaction groupCredits maybeYear =
    case maybeYear of
        Nothing ->
            Nothing

        Just year ->
            Just
                { months =
                    year.months
                        |> Dict.update transactionId.month (removeTransactionFromMonth transactionId transaction groupCredits)
                , totalGroupCredits =
                    year.totalGroupCredits
                        |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
                }


removeTransactionFromMonth : TransactionId -> Transaction -> Dict String (Amount Credit) -> Maybe Month -> Maybe Month
removeTransactionFromMonth transactionId transaction groupCredits maybeMonth =
    case maybeMonth of
        Nothing ->
            Nothing

        Just month ->
            Just
                { days =
                    month.days
                        |> Dict.update transactionId.day (removeTransactionFromDay transaction.groupMembersKey groupCredits)
                , totalGroupCredits =
                    month.totalGroupCredits
                        |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
                }


removeTransactionFromDay : String -> Dict String (Amount Credit) -> Maybe Day -> Maybe Day
removeTransactionFromDay groupMembersKey groupCredits maybeDay =
    case maybeDay of
        Nothing ->
            Nothing

        Just day ->
            Just
                { transactions = day.transactions
                , totalGroupCredits =
                    day.totalGroupCredits
                        |> addToTotalGroupCredits groupMembersKey groupCredits
                }


{-| Find a specific transaction by ID
-}
findTransaction : TransactionId -> Model -> Maybe Transaction
findTransaction transactionId model =
    Dict.get transactionId.year model.years
        |> Maybe.andThen (.months >> Dict.get transactionId.month)
        |> Maybe.andThen (.days >> Dict.get transactionId.day)
        |> Maybe.andThen (.transactions >> Array.get transactionId.index)


{-| Get group members key for a spending
-}
getGroupMembersKey : List String -> Model -> ( String, Set String )
getGroupMembersKey groups model =
    let
        groupMembers =
            groups
                |> List.map
                    (\group ->
                        Dict.get group model.groups
                            |> Maybe.map Dict.keys
                            |> Maybe.withDefault [ group ]
                    )
                |> List.concat
                |> Set.fromList
    in
    ( Set.toList groupMembers
        |> List.filterMap (flip Dict.get model.persons)
        |> List.map (.id >> String.fromInt)
        |> String.join ","
    , groupMembers
    )


validateSpendingTransactions : Amount Credit -> List SpendingTransaction -> Result String (List SpendingTransaction)
validateSpendingTransactions (Amount total) transactions =
    let
        normalizedTransactions =
            normalizeSpendingTransactions transactions

        { credits, debits } =
            spendingTransactionTotals normalizedTransactions
    in
    if List.isEmpty normalizedTransactions then
        Err "A spending needs at least one transaction"

    else if
        List.all isBalancedTransaction normalizedTransactions
            && credits
            == debits
            && credits
            == total
            && total
            /= 0
    then
        Ok normalizedTransactions

    else
        Err "Spending total must match total credits and total debits"


normalizeSpendingTransactions : List SpendingTransaction -> List SpendingTransaction
normalizeSpendingTransactions transactions =
    transactions
        |> List.foldl
            (\transaction ->
                Dict.update
                    (normalizedTransactionKey transaction)
                    (\maybeTransaction ->
                        case maybeTransaction of
                            Nothing ->
                                Just transaction

                            Just existingTransaction ->
                                Just
                                    { existingTransaction
                                        | amount = addAmountToAmount existingTransaction.amount transaction.amount
                                    }
                    )
            )
            Dict.empty
        |> Dict.values
        |> List.filter
            (\transaction ->
                case transaction.amount of
                    Amount amount ->
                        amount /= 0
            )


isBalancedTransaction : SpendingTransaction -> Bool
isBalancedTransaction transaction =
    case transaction.amount of
        Amount amount ->
            String.trim transaction.group
                /= ""
                && amount
                /= 0


totalAmount : Dict String (Amount a) -> Int
totalAmount =
    Dict.values
        >> List.foldl (\(Amount amount) total -> total + amount) 0


toSpendingTransaction : TransactionId -> Transaction -> SpendingTransaction
toSpendingTransaction transactionId transaction =
    { year = transactionId.year
    , month = transactionId.month
    , day = transactionId.day
    , secondaryDescription = transaction.secondaryDescription
    , group = transaction.group
    , amount = transaction.amount
    , side = transaction.side
    }


pendingTransactionsForSpending : SpendingId -> SpendingMetadata -> SpendingTransaction -> PendingTransaction
pendingTransactionsForSpending spendingId metadata transaction =
    { spendingId = spendingId
    , year = transaction.year
    , month = transaction.month
    , day = transaction.day
    , secondaryDescription = transaction.secondaryDescription
    , group = transaction.group
    , amount = transaction.amount
    , side = transaction.side
    , groupMembersKey = metadata.groupMembersKey
    , groupMembers = metadata.groupMembers
    , status = Active
    }


storedTransaction : PendingTransaction -> Transaction
storedTransaction pending =
    { spendingId = pending.spendingId
    , secondaryDescription = pending.secondaryDescription
    , group = pending.group
    , amount = pending.amount
    , side = pending.side
    , groupMembersKey = pending.groupMembersKey
    , groupMembers = pending.groupMembers
    , status = pending.status
    }


assignTransactionIds : Model -> List PendingTransaction -> List TransactionId
assignTransactionIds model pendingTransactions =
    pendingTransactions
        |> List.foldl
            (\pending ( nextIndexes, transactionIds ) ->
                let
                    dateKey =
                        ( pending.year, pending.month, pending.day )

                    nextIndex =
                        Dict.get dateKey nextIndexes
                            |> Maybe.withDefault (dayTransactionCount pending.year pending.month pending.day model)
                in
                ( Dict.insert dateKey (nextIndex + 1) nextIndexes
                , { year = pending.year
                  , month = pending.month
                  , day = pending.day
                  , index = nextIndex
                  }
                    :: transactionIds
                )
            )
            ( Dict.empty, [] )
        |> (\( _, transactionIds ) -> List.reverse transactionIds)


createSpendingInModel : String -> Amount Credit -> List SpendingTransaction -> Model -> Model
createSpendingInModel description total spendingTransactions model =
    let
        spendingId =
            Array.length model.spendings

        spendingMetadata =
            buildSpendingMetadata model spendingTransactions

        pendingTransactions =
            spendingTransactions
                |> List.map (pendingTransactionsForSpending spendingId spendingMetadata)

        transactionIds =
            assignTransactionIds model pendingTransactions

        updatedModel =
            { model
                | spendings =
                    Array.push
                        { description = description
                        , total = total
                        , transactionIds = transactionIds
                        , status = Active
                        }
                        model.spendings
            }
    in
    List.foldl addTransactionToModel updatedModel pendingTransactions


setSpendingStatus : SpendingId -> TransactionStatus -> Model -> Model
setSpendingStatus spendingId status model =
    { model
        | spendings =
            case Array.get spendingId model.spendings of
                Nothing ->
                    model.spendings

                Just spending ->
                    Array.set spendingId { spending | status = status } model.spendings
    }


setTransactionStatuses : SpendingId -> TransactionStatus -> Model -> Model
setTransactionStatuses spendingId status model =
    Array.get spendingId model.spendings
        |> Maybe.map
            (.transactionIds
                >> List.foldl
                    (\transactionId updatedModel ->
                        { updatedModel
                            | years =
                                Dict.update transactionId.year
                                    (Maybe.map
                                        (\year ->
                                            { year
                                                | months =
                                                    Dict.update transactionId.month
                                                        (Maybe.map
                                                            (\month ->
                                                                { month
                                                                    | days =
                                                                        Dict.update transactionId.day
                                                                            (Maybe.map
                                                                                (\day ->
                                                                                    { day
                                                                                        | transactions =
                                                                                            case Array.get transactionId.index day.transactions of
                                                                                                Nothing ->
                                                                                                    day.transactions

                                                                                                Just transaction ->
                                                                                                    if transaction.status == Active then
                                                                                                        Array.set transactionId.index { transaction | status = status } day.transactions

                                                                                                    else
                                                                                                        day.transactions
                                                                                    }
                                                                                )
                                                                            )
                                                                            month.days
                                                                }
                                                            )
                                                        )
                                                        year.months
                                            }
                                        )
                                    )
                                    updatedModel.years
                        }
                    )
                    model
            )
        |> Maybe.withDefault model


type alias TransactionKey =
    ( Int, Int, ( Int, String ) )


type alias NormalizedTransactionKey =
    ( TransactionKey, String, String )


transactionKey : { a | year : Int, month : Int, day : Int, secondaryDescription : String } -> TransactionKey
transactionKey transaction =
    ( transaction.year, transaction.month, ( transaction.day, transaction.secondaryDescription ) )


normalizedTransactionKey : SpendingTransaction -> NormalizedTransactionKey
normalizedTransactionKey transaction =
    ( transactionKey transaction
    , transaction.group
    , case transaction.side of
        CreditTransaction ->
            "credit"

        DebitTransaction ->
            "debit"
    )


type alias SpendingTransactionTotals =
    { credits : Int
    , debits : Int
    }


spendingTransactionTotals : List SpendingTransaction -> SpendingTransactionTotals
spendingTransactionTotals transactions =
    transactions
        |> List.foldl
            (\transaction totals ->
                case transaction.amount of
                    Amount amount ->
                        case transaction.side of
                            CreditTransaction ->
                                { totals | credits = totals.credits + amount }

                            DebitTransaction ->
                                { totals | debits = totals.debits + amount }
            )
            { credits = 0
            , debits = 0
            }


type alias SpendingMetadata =
    { groupMembersKey : String
    , groupMembers : Set String
    }


buildSpendingMetadata : Model -> List SpendingTransaction -> SpendingMetadata
buildSpendingMetadata model transactions =
    let
        groups =
            transactions
                |> List.map .group

        ( groupMembersKey, groupMembers ) =
            getGroupMembersKey groups model
    in
    { groupMembersKey = groupMembersKey
    , groupMembers = groupMembers
    }


groupCreditsForTransaction :
    { a | group : String, amount : Amount (), side : TransactionSide }
    -> Dict String (Amount Credit)
groupCreditsForTransaction transaction =
    case ( transaction.side, transaction.amount ) of
        ( CreditTransaction, Amount amount ) ->
            Dict.singleton transaction.group (Amount amount)

        ( DebitTransaction, Amount amount ) ->
            Dict.singleton transaction.group (Amount -amount)


{-| Add a transaction to the model, updating all totals and person belongsTo sets
-}
addTransactionToModel : PendingTransaction -> Model -> Model
addTransactionToModel transaction model =
    let
        groupCredits =
            groupCreditsForTransaction transaction
    in
    { model
        | years =
            model.years
                |> Dict.update transaction.year (addTransactionToYear transaction groupCredits >> Just)
        , totalGroupCredits =
            model.totalGroupCredits
                |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
        , persons =
            Dict.map
                (\name person ->
                    if Set.member name transaction.groupMembers then
                        { person
                            | belongsTo =
                                Set.insert transaction.groupMembersKey person.belongsTo
                        }

                    else
                        person
                )
                model.persons
    }


{-| Remove a transaction from the model totals (but keep the transaction record marked as deleted)
-}
removeTransactionFromModel : ( TransactionId, Transaction ) -> Model -> Model
removeTransactionFromModel ( transactionId, transaction ) model =
    let
        -- Convert debits to negative credits for aggregation and negate the whole
        groupCredits =
            groupCreditsForTransaction transaction
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
    in
    { model
        | years =
            model.years
                |> Dict.update transactionId.year (removeTransactionFromYear transactionId transaction groupCredits)
        , totalGroupCredits =
            model.totalGroupCredits
                |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
    }


getSpendingTransactionsWithIds : SpendingId -> Model -> List ( TransactionId, Transaction )
getSpendingTransactionsWithIds spendingId model =
    Array.get spendingId model.spendings
        |> Maybe.map
            (.transactionIds
                >> List.filterMap
                    (\transactionId ->
                        findTransaction transactionId model
                            |> Maybe.andThen
                                (\transaction ->
                                    if transaction.spendingId == spendingId then
                                        -- this conditional should always be true if the model is correctly maintained
                                        Just ( transactionId, transaction )

                                    else
                                        -- ideally we should raise an alert in this case
                                        Nothing
                                )
                    )
            )
        |> Maybe.withDefault []


spendingTransactionsForDetails : SpendingId -> Model -> List SpendingTransaction
spendingTransactionsForDetails spendingId model =
    getSpendingTransactionsWithIds spendingId model
        |> List.filter (\( _, transaction ) -> transaction.status == Active)
        |> List.sortBy (\( transactionId, _ ) -> ( transactionId.year, transactionId.month, ( transactionId.day, transactionId.index ) ))
        |> List.map (\( transactionId, transaction ) -> toSpendingTransaction transactionId transaction)


transactionDescription : Spending -> Transaction -> String
transactionDescription spending transaction =
    if String.trim transaction.secondaryDescription == "" then
        spending.description

    else
        spending.description ++ " — " ++ transaction.secondaryDescription


groupTransactionForList :
    Model
    -> String
    -> ( TransactionId, Transaction )
    ->
        Maybe
            { transactionId : TransactionId
            , spendingId : SpendingId
            , description : String
            , year : Int
            , month : Int
            , day : Int
            , total : Amount Debit
            , share : Amount Debit
            }
groupTransactionForList model group ( transactionId, transaction ) =
    if transaction.status /= Active then
        Nothing

    else
        Array.get transaction.spendingId model.spendings
            |> Maybe.andThen
                (\spending ->
                    if spending.status /= Active then
                        Nothing

                    else if transaction.group /= group then
                        Nothing

                    else
                        Just
                            { transactionId = transactionId
                            , spendingId = transaction.spendingId
                            , description = transactionDescription spending transaction
                            , year = transactionId.year
                            , month = transactionId.month
                            , day = transactionId.day
                            , total = spending.total |> (\(Amount amount) -> Amount amount)
                            , share =
                                case ( transaction.side, transaction.amount ) of
                                    ( CreditTransaction, Amount amount ) ->
                                        toDebit (Amount amount)

                                    ( DebitTransaction, Amount amount ) ->
                                        Amount amount
                            }
                )


allTransactionsWithIds : Model -> List ( TransactionId, Transaction )
allTransactionsWithIds model =
    Dict.foldr
        (\year yearRecord accYears ->
            Dict.foldr
                (\month monthRecord accMonths ->
                    Dict.foldr
                        (\day dayRecord accDays ->
                            (dayRecord.transactions
                                |> Array.toIndexedList
                                |> List.map
                                    (\( index, transaction ) ->
                                        ( { year = year
                                          , month = month
                                          , day = day
                                          , index = index
                                          }
                                        , transaction
                                        )
                                    )
                            )
                                ++ accDays
                        )
                        accMonths
                        monthRecord.days
                )
                accYears
                yearRecord.months
        )
        []
        model.years
