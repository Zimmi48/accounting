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
      , nextSpendingId = 0
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
            case Array.get spendingId model.spendings of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending not found") )

                Just spending ->
                    if spending.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending is already deleted or replaced") )

                    else
                        case validateSpendingTransactions total transactions of
                            Err errorMessage ->
                                ( model, Lamdera.sendToFrontend clientId (SpendingError errorMessage) )

                            Ok normalizedTransactions ->
                                let
                                    activeTransactions =
                                        getSpendingTransactions spendingId model
                                            |> List.filter (\transaction -> transaction.status == Active)

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
            case Array.get spendingId model.spendings of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending not found") )

                Just spending ->
                    if spending.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (SpendingError "Spending is already deleted or replaced") )

                    else
                        let
                            activeTransactions =
                                getSpendingTransactions spendingId model
                                    |> List.filter (\transaction -> transaction.status == Active)

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
                    Dict.foldr
                        (\_ { months } accYears ->
                            Dict.foldr
                                (\_ { days } accMonths ->
                                    Dict.foldr
                                        (\_ dayRecord accDays ->
                                            dayRecord.transactions
                                                |> List.filterMap (groupTransactionForList model group)
                                                |> (++) accDays
                                        )
                                        accMonths
                                        days
                                )
                                accYears
                                months
                        )
                        []
                        model.years
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

                Err error ->
                    -- Debug.log (Debug.toString error)
                    ( model, Cmd.none )


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


listGet : Int -> List a -> Maybe a
listGet index list =
    list
        |> List.drop index
        |> List.head


findTransaction : TransactionId -> Model -> Maybe Transaction
findTransaction transactionId model =
    Dict.get transactionId.year model.years
        |> Maybe.andThen (.months >> Dict.get transactionId.month)
        |> Maybe.andThen (.days >> Dict.get transactionId.day)
        |> Maybe.andThen (.transactions >> listGet transactionId.index)


dayTransactionCount : Int -> Int -> Int -> Model -> Int
dayTransactionCount year month day model =
    Dict.get year model.years
        |> Maybe.andThen (.months >> Dict.get month)
        |> Maybe.andThen (.days >> Dict.get day)
        |> Maybe.map (.transactions >> List.length)
        |> Maybe.withDefault 0


addTransactionToYear : Transaction -> String -> Dict String (Amount Credit) -> Maybe Year -> Year
addTransactionToYear transaction groupMembersKey groupCredits maybeYear =
    case maybeYear of
        Nothing ->
            { months =
                Dict.singleton transaction.id.month
                    (addTransactionToMonth transaction groupMembersKey groupCredits Nothing)
            , totalGroupCredits =
                Dict.singleton groupMembersKey groupCredits
            }

        Just year ->
            { months =
                year.months
                    |> Dict.update transaction.id.month (addTransactionToMonth transaction groupMembersKey groupCredits >> Just)
            , totalGroupCredits =
                year.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey groupCredits
            }


addTransactionToMonth : Transaction -> String -> Dict String (Amount Credit) -> Maybe Month -> Month
addTransactionToMonth transaction groupMembersKey groupCredits maybeMonth =
    case maybeMonth of
        Nothing ->
            { days =
                Dict.singleton transaction.id.day
                    (addTransactionToDay transaction groupMembersKey groupCredits Nothing)
            , totalGroupCredits =
                Dict.singleton groupMembersKey groupCredits
            }

        Just month ->
            { days =
                month.days
                    |> Dict.update transaction.id.day (addTransactionToDay transaction groupMembersKey groupCredits >> Just)
            , totalGroupCredits =
                month.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey groupCredits
            }


addTransactionToDay : Transaction -> String -> Dict String (Amount Credit) -> Maybe Day -> Day
addTransactionToDay transaction groupMembersKey groupCredits maybeDay =
    case maybeDay of
        Nothing ->
            { transactions = [ transaction ]
            , totalGroupCredits =
                Dict.singleton groupMembersKey groupCredits
            }

        Just day ->
            { transactions = transaction :: day.transactions
            , totalGroupCredits =
                day.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey groupCredits
            }


removeTransactionFromYear : Transaction -> String -> Dict String (Amount Credit) -> Maybe Year -> Maybe Year
removeTransactionFromYear transaction groupMembersKey groupCredits maybeYear =
    case maybeYear of
        Nothing ->
            Nothing

        Just year ->
            Just
                { months =
                    year.months
                        |> Dict.update transaction.id.month (removeTransactionFromMonth transaction groupMembersKey groupCredits)
                , totalGroupCredits =
                    year.totalGroupCredits
                        |> addToTotalGroupCredits groupMembersKey groupCredits
                }


removeTransactionFromMonth : Transaction -> String -> Dict String (Amount Credit) -> Maybe Month -> Maybe Month
removeTransactionFromMonth transaction groupMembersKey groupCredits maybeMonth =
    case maybeMonth of
        Nothing ->
            Nothing

        Just month ->
            Just
                { days =
                    month.days
                        |> Dict.update transaction.id.day (removeTransactionFromDay groupMembersKey groupCredits)
                , totalGroupCredits =
                    month.totalGroupCredits
                        |> addToTotalGroupCredits groupMembersKey groupCredits
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
            > 0
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
                        amount > 0
            )


isBalancedTransaction : SpendingTransaction -> Bool
isBalancedTransaction transaction =
    case transaction.amount of
        Amount amount ->
            String.trim transaction.group
                /= ""
                && amount
                > 0


totalAmount : Dict String (Amount a) -> Int
totalAmount =
    Dict.values
        >> List.foldl (\(Amount amount) total -> total + amount) 0


toSpendingTransaction : Transaction -> SpendingTransaction
toSpendingTransaction transaction =
    { year = transaction.id.year
    , month = transaction.id.month
    , day = transaction.id.day
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


assignTransactionIds : Model -> List PendingTransaction -> List Transaction
assignTransactionIds model pendingTransactions =
    pendingTransactions
        |> List.foldl
            (\pending ( nextIndexes, transactions ) ->
                let
                    dateKey =
                        ( pending.year, pending.month, pending.day )

                    nextIndex =
                        Dict.get dateKey nextIndexes
                            |> Maybe.withDefault (dayTransactionCount pending.year pending.month pending.day model)
                in
                ( Dict.insert dateKey (nextIndex + 1) nextIndexes
                , { id =
                        { year = pending.year
                        , month = pending.month
                        , day = pending.day
                        , index = nextIndex
                        }
                  , spendingId = pending.spendingId
                  , secondaryDescription = pending.secondaryDescription
                  , group = pending.group
                  , amount = pending.amount
                  , side = pending.side
                  , groupMembersKey = pending.groupMembersKey
                  , groupMembers = pending.groupMembers
                  , status = pending.status
                  }
                    :: transactions
                )
            )
            ( Dict.empty, [] )
        |> (\( _, transactions ) -> List.reverse transactions)


createSpendingInModel : String -> Amount Credit -> List SpendingTransaction -> Model -> Model
createSpendingInModel description total spendingTransactions model =
    let
        spendingId =
            model.nextSpendingId

        spendingMetadata =
            buildSpendingMetadata model spendingTransactions

        storedTransactions =
            spendingTransactions
                |> List.map (pendingTransactionsForSpending spendingId spendingMetadata)
                |> assignTransactionIds model

        updatedModel =
            { model
                | spendings =
                    Array.push
                        { description = description
                        , total = total
                        , transactionIds = List.map .id storedTransactions
                        , status = Active
                        }
                        model.spendings
                , nextSpendingId = spendingId + 1
            }
    in
    List.foldl addTransactionToModel updatedModel storedTransactions


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
    { model
        | years =
            Dict.map
                (\_ year ->
                    { year
                        | months =
                            Dict.map
                                (\_ month ->
                                    { month
                                        | days =
                                            Dict.map
                                                (\_ day ->
                                                    { day
                                                        | transactions =
                                                            List.map
                                                                (\transaction ->
                                                                    if transaction.spendingId == spendingId && transaction.status == Active then
                                                                        { transaction | status = status }

                                                                    else
                                                                        transaction
                                                                )
                                                                day.transactions
                                                    }
                                                )
                                                month.days
                                    }
                                )
                                year.months
                    }
                )
                model.years
    }


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


groupCreditsForTransaction : Transaction -> Dict String (Amount Credit)
groupCreditsForTransaction transaction =
    case ( transaction.side, transaction.amount ) of
        ( CreditTransaction, Amount amount ) ->
            Dict.singleton transaction.group (Amount amount)

        ( DebitTransaction, Amount amount ) ->
            Dict.singleton transaction.group (Amount -amount)


addTransactionToModel : Transaction -> Model -> Model
addTransactionToModel transaction model =
    let
        groupCredits =
            groupCreditsForTransaction transaction
    in
    { model
        | years =
            model.years
                |> Dict.update transaction.id.year (addTransactionToYear transaction transaction.groupMembersKey groupCredits >> Just)
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


removeTransactionFromModel : Transaction -> Model -> Model
removeTransactionFromModel transaction model =
    let
        groupCredits =
            groupCreditsForTransaction transaction
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
    in
    { model
        | years =
            model.years
                |> Dict.update transaction.id.year (removeTransactionFromYear transaction transaction.groupMembersKey groupCredits)
        , totalGroupCredits =
            model.totalGroupCredits
                |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
    }


getSpendingTransactions : SpendingId -> Model -> List Transaction
getSpendingTransactions spendingId model =
    Array.get spendingId model.spendings
        |> Maybe.map
            (.transactionIds
                >> List.filterMap (\transactionId -> findTransaction transactionId model)
            )
        |> Maybe.withDefault []


spendingTransactionsForDetails : SpendingId -> Model -> List SpendingTransaction
spendingTransactionsForDetails spendingId model =
    getSpendingTransactions spendingId model
        |> List.filter (\transaction -> transaction.status == Active)
        |> List.sortBy (\transaction -> ( transaction.id.year, transaction.id.month, ( transaction.id.day, transaction.id.index ) ))
        |> List.map toSpendingTransaction


transactionDescription : Spending -> Transaction -> String
transactionDescription spending transaction =
    if String.trim transaction.secondaryDescription == "" then
        spending.description

    else
        spending.description ++ " — " ++ transaction.secondaryDescription


groupTransactionForList :
    Model
    -> String
    -> Transaction
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
groupTransactionForList model group transaction =
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
                            { transactionId = transaction.id
                            , spendingId = transaction.spendingId
                            , description = transactionDescription spending transaction
                            , year = transaction.id.year
                            , month = transaction.id.month
                            , day = transaction.id.day
                            , total = spending.total |> (\(Amount amount) -> Amount amount)
                            , share =
                                case ( transaction.side, transaction.amount ) of
                                    ( CreditTransaction, Amount amount ) ->
                                        toDebit (Amount amount)

                                    ( DebitTransaction, Amount amount ) ->
                                        Amount amount
                            }
                )
