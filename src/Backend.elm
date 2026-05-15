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
    , groupId : GroupId
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
    ( { spendings = Array.empty
      , groups = Dict.empty
      , persons = Dict.empty
      , nextId = 0
      , totalGroupCredits = Dict.empty
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
                let
                    personId =
                        model.nextId
                in
                ( { model
                    | persons =
                        Dict.insert personId
                            { name = person
                            , belongsTo = Set.empty
                            }
                            model.persons
                    , groups =
                        Dict.insert personId
                            { name = person
                            , members = Dict.singleton personId (Share 1)
                            , years = Dict.empty
                            , totalCredit = Amount 0
                            }
                            model.groups
                    , nextId = personId + 1
                  }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model
                , Lamdera.sendToFrontend clientId (NameAlreadyExists person)
                )

        ( True, CreateGroup name members ) ->
            if checkValidName model name then
                case storedGroupMembersForNames model members of
                    Err errorMessage ->
                        ( model, Lamdera.sendToFrontend clientId (SpendingError errorMessage) )

                    Ok storedMembers ->
                        let
                            groupId =
                                model.nextId
                        in
                        ( { model
                            | groups =
                                Dict.insert groupId
                                    { name = name
                                    , members = storedMembers
                                    , years = Dict.empty
                                    , totalCredit = Amount 0
                                    }
                                    model.groups
                            , nextId = groupId + 1
                          }
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
                    case createSpendingInModel description total normalizedTransactions model of
                        Ok updatedModel ->
                            ( updatedModel
                            , Lamdera.sendToFrontend clientId OperationSuccessful
                            )

                        Err errorMessage ->
                            ( model, Lamdera.sendToFrontend clientId (SpendingError errorMessage) )

        ( True, EditSpending { spendingId, description, total, transactions } ) ->
            case editSpendingInModel spendingId description total transactions model of
                Ok updatedModel ->
                    ( updatedModel
                    , Lamdera.sendToFrontend clientId OperationSuccessful
                    )

                Err errorMessage ->
                    ( model, Lamdera.sendToFrontend clientId (SpendingError errorMessage) )

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
            , model.persons
                |> Dict.values
                |> List.map .name
                |> List.sort
                |> autocomplete clientId prefix AutocompletePersonPrefix InvalidPersonPrefix
            )

        ( True, AutocompleteGroup prefix ) ->
            ( model
            , model.groups
                |> Dict.values
                |> List.map .name
                |> List.sort
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
            case userGroupsForPerson user model of
                Nothing ->
                    ( model
                    , Cmd.none
                    )

                Just userGroups ->
                    ( model
                    , Lamdera.sendToFrontend clientId
                        (ListUserGroups
                            { user = user
                            , debitors = userGroups.debitors
                            , creditors = userGroups.creditors
                            }
                        )
                    )

        ( True, RequestGroupTransactions group ) ->
            let
                transactions =
                    findGroupByName group model
                        |> Maybe.map
                            (\( groupId, storedGroup ) ->
                                allTransactionsWithIdsForGroup groupId storedGroup
                                    |> List.filterMap (groupTransactionForList model)
                            )
                        |> Maybe.withDefault []
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
    case findGroupByName group model of
        Nothing ->
            -- persons are automatically single-member groups
            Dict.singleton group (Share 1)

        Just ( _, members ) ->
            groupMembersForFrontend model members


type alias UserGroupsPayload =
    { debitors : List ( String, Group, Amount Debit )
    , creditors : List ( String, Group, Amount Credit )
    }


userGroupsForPerson : String -> Model -> Maybe UserGroupsPayload
userGroupsForPerson user model =
    findPersonByName user model
        |> Maybe.map
            (\person ->
                let
                    groupsWithAmounts =
                        person.belongsTo
                            |> Set.toList
                            |> List.foldl
                                (\key aggregated ->
                                    Dict.get key model.totalGroupCredits
                                        |> Maybe.withDefault Dict.empty
                                        |> addAmounts aggregated
                                )
                                Dict.empty
                            |> Dict.toList
                in
                { debitors =
                    groupsWithAmounts
                        |> List.filter (\( _, Amount credit ) -> credit < 0)
                        |> List.map
                            (\( group, Amount debit ) ->
                                ( group
                                , getGroupMembers model group
                                , Amount -debit
                                )
                            )
                , creditors =
                    groupsWithAmounts
                        |> List.filter (\( _, Amount credit ) -> credit > 0)
                        |> List.map
                            (\( group, credit ) ->
                                ( group
                                , getGroupMembers model group
                                , credit
                                )
                            )
                }
            )


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
        && (findPersonByName name model == Nothing)
        && (findGroupByName name model == Nothing)


findPersonByName : String -> Model -> Maybe Person
findPersonByName personName model =
    model.persons
        |> Dict.values
        |> List.filter (\person -> person.name == personName)
        |> List.head


findPersonNameById : PersonId -> Model -> Maybe String
findPersonNameById personId model =
    model.persons
        |> Dict.get personId
        |> Maybe.map .name


findPersonIdByName : String -> Model -> Maybe PersonId
findPersonIdByName personName model =
    model.persons
        |> Dict.toList
        |> List.filterMap
            (\( personId, person ) ->
                if person.name == personName then
                    Just personId

                else
                    Nothing
            )
        |> List.head


findGroupByName : String -> Model -> Maybe ( GroupId, StoredGroup )
findGroupByName groupName model =
    model.groups
        |> Dict.toList
        |> List.filter (\( _, group ) -> group.name == groupName)
        |> List.head


groupMembersForFrontend : Model -> StoredGroup -> Group
groupMembersForFrontend model group =
    group.members
        |> Dict.toList
        |> List.filterMap
            (\( personId, share ) ->
                findPersonNameById personId model
                    |> Maybe.map (\personName -> ( personName, share ))
            )
        |> Dict.fromList


storedGroupMembersForNames : Model -> Group -> Result String StoredGroupMembers
storedGroupMembersForNames model members =
    members
        |> Dict.toList
        |> List.map
            (\( personName, share ) ->
                findPersonIdByName personName model
                    |> Maybe.map (\personId -> Ok ( personId, share ))
                    |> Maybe.withDefault (Err ("Unknown person: " ++ personName))
            )
        |> List.foldr
            (\result acc ->
                case ( result, acc ) of
                    ( Ok ( personId, share ), Ok storedMembers ) ->
                        Ok (Dict.insert personId share storedMembers)

                    ( Err message, _ ) ->
                        Err message

                    ( _, Err message ) ->
                        Err message
            )
            (Ok Dict.empty)


updateGroupById : GroupId -> (StoredGroup -> StoredGroup) -> Model -> Model
updateGroupById groupId transform model =
    { model
        | groups =
            Dict.update groupId (Maybe.map transform) model.groups
    }


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


dayTransactionCount : GroupId -> Int -> Int -> Int -> Model -> Int
dayTransactionCount groupId year month day model =
    Dict.get groupId model.groups
        |> Maybe.andThen (.years >> Dict.get year)
        |> Maybe.andThen (.months >> Dict.get month)
        |> Maybe.andThen (.days >> Dict.get day)
        |> Maybe.map (.transactions >> Array.length)
        |> Maybe.withDefault 0


addTransactionToYear : PendingTransaction -> Amount Credit -> Maybe Year -> Year
addTransactionToYear transaction groupCredit maybeYear =
    case maybeYear of
        Nothing ->
            { months =
                Dict.singleton transaction.month
                    (addTransactionToMonth transaction groupCredit Nothing)
            , totalCredit = groupCredit
            }

        Just year ->
            { months =
                year.months
                    |> Dict.update transaction.month (addTransactionToMonth transaction groupCredit >> Just)
            , totalCredit =
                addAmountToAmount year.totalCredit groupCredit
            }


addTransactionToMonth : PendingTransaction -> Amount Credit -> Maybe Month -> Month
addTransactionToMonth transaction groupCredit maybeMonth =
    case maybeMonth of
        Nothing ->
            { days =
                Dict.singleton transaction.day
                    (addTransactionToDay transaction groupCredit Nothing)
            , totalCredit = groupCredit
            }

        Just month ->
            { days =
                month.days
                    |> Dict.update transaction.day (addTransactionToDay transaction groupCredit >> Just)
            , totalCredit =
                addAmountToAmount month.totalCredit groupCredit
            }


addTransactionToDay : PendingTransaction -> Amount Credit -> Maybe Day -> Day
addTransactionToDay transaction groupCredit maybeDay =
    case maybeDay of
        Nothing ->
            { transactions = Array.fromList [ storedTransaction transaction ]
            , totalCredit = groupCredit
            }

        Just day ->
            { transactions = Array.push (storedTransaction transaction) day.transactions
            , totalCredit =
                addAmountToAmount day.totalCredit groupCredit
            }


removeTransactionFromYear : TransactionId -> Transaction -> Amount Credit -> Maybe Year -> Maybe Year
removeTransactionFromYear transactionId transaction groupCredit maybeYear =
    case maybeYear of
        Nothing ->
            Nothing

        Just year ->
            Just
                { months =
                    year.months
                        |> Dict.update transactionId.month (removeTransactionFromMonth transactionId transaction groupCredit)
                , totalCredit =
                    addAmountToAmount year.totalCredit groupCredit
                }


removeTransactionFromMonth : TransactionId -> Transaction -> Amount Credit -> Maybe Month -> Maybe Month
removeTransactionFromMonth transactionId transaction groupCredit maybeMonth =
    case maybeMonth of
        Nothing ->
            Nothing

        Just month ->
            Just
                { days =
                    month.days
                        |> Dict.update transactionId.day (removeTransactionFromDay groupCredit)
                , totalCredit =
                    addAmountToAmount month.totalCredit groupCredit
                }


removeTransactionFromDay : Amount Credit -> Maybe Day -> Maybe Day
removeTransactionFromDay groupCredit maybeDay =
    case maybeDay of
        Nothing ->
            Nothing

        Just day ->
            Just
                { transactions = day.transactions
                , totalCredit =
                    addAmountToAmount day.totalCredit groupCredit
                }


{-| Find a specific transaction by ID
-}
findTransaction : TransactionId -> Model -> Maybe Transaction
findTransaction transactionId model =
    Dict.get transactionId.groupId model.groups
        |> Maybe.andThen (.years >> Dict.get transactionId.year)
        |> Maybe.andThen (.months >> Dict.get transactionId.month)
        |> Maybe.andThen (.days >> Dict.get transactionId.day)
        |> Maybe.andThen (.transactions >> Array.get transactionId.index)


{-| Get group members key for a spending
-}
getGroupMembersKey : List String -> Model -> Result String ( String, Set String )
getGroupMembersKey groups model =
    groups
        |> List.foldl
            (\group acc ->
                case ( resolveGroupMembers model group, acc ) of
                    ( Ok members, Ok groupMembers ) ->
                        Ok (Dict.union groupMembers members)

                    ( Err errorMessage, _ ) ->
                        Err errorMessage

                    ( _, Err errorMessage ) ->
                        Err errorMessage
            )
            (Ok Dict.empty)
        |> Result.map
            (\groupMembers ->
                ( groupMembers
                    |> Dict.keys
                    |> List.sort
                    |> List.map String.fromInt
                    |> String.join ","
                , groupMembers
                    |> Dict.values
                    |> Set.fromList
                )
            )


resolveGroupMembers : Model -> String -> Result String (Dict PersonId String)
resolveGroupMembers model groupName =
    case findGroupByName groupName model of
        Nothing ->
            Err ("Unknown group or account: " ++ groupName)

        Just ( _, group ) ->
            group.members
                |> Dict.keys
                |> List.foldl
                    (\personId acc ->
                        case ( findPersonNameById personId model, acc ) of
                            ( Just personName, Ok groupMembers ) ->
                                Ok (Dict.insert personId personName groupMembers)

                            ( Nothing, _ ) ->
                                Err ("Unknown person id in group: " ++ String.fromInt personId)

                            ( _, Err errorMessage ) ->
                                Err errorMessage
                    )
                    (Ok Dict.empty)


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


pendingTransactionForSpending : SpendingId -> GroupId -> SpendingMetadata -> SpendingTransaction -> PendingTransaction
pendingTransactionForSpending spendingId groupId metadata transaction =
    { spendingId = spendingId
    , groupId = groupId
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
                        ( pending.groupId, ( pending.year, pending.month, pending.day ) )

                    nextIndex =
                        Dict.get dateKey nextIndexes
                            |> Maybe.withDefault (dayTransactionCount pending.groupId pending.year pending.month pending.day model)
                in
                ( Dict.insert dateKey (nextIndex + 1) nextIndexes
                , { groupId = pending.groupId
                  , year = pending.year
                  , month = pending.month
                  , day = pending.day
                  , index = nextIndex
                  }
                    :: transactionIds
                )
            )
            ( Dict.empty, [] )
        |> (\( _, transactionIds ) -> List.reverse transactionIds)


groupIdForName : Model -> String -> Result String GroupId
groupIdForName model groupName =
    findGroupByName groupName model
        |> Maybe.map (Tuple.first >> Ok)
        |> Maybe.withDefault (Err ("Unknown group or account: " ++ groupName))


pendingTransactionsForSpending : SpendingId -> Model -> List SpendingTransaction -> Result String (List PendingTransaction)
pendingTransactionsForSpending spendingId model spendingTransactions =
    buildSpendingMetadata model spendingTransactions
        |> Result.andThen
            (\metadata ->
                spendingTransactions
                    |> List.map
                        (\transaction ->
                            groupIdForName model transaction.group
                                |> Result.map (\groupId -> pendingTransactionForSpending spendingId groupId metadata transaction)
                        )
                    |> List.foldr
                        (\result acc ->
                            case ( result, acc ) of
                                ( Ok transaction, Ok transactions ) ->
                                    Ok (transaction :: transactions)

                                ( Err message, _ ) ->
                                    Err message

                                ( _, Err message ) ->
                                    Err message
                        )
                        (Ok [])
            )


createSpendingInModel : String -> Amount Credit -> List SpendingTransaction -> Model -> Result String Model
createSpendingInModel description total spendingTransactions model =
    let
        spendingId =
            Array.length model.spendings
    in
    pendingTransactionsForSpending spendingId model spendingTransactions
        |> Result.map
            (\pendingTransactions ->
                let
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
            )


editSpendingInModel : SpendingId -> String -> Amount Credit -> List SpendingTransaction -> Model -> Result String Model
editSpendingInModel spendingId description total spendingTransactions model =
    case Array.get spendingId model.spendings of
        Nothing ->
            Err "Spending not found"

        Just spending ->
            if spending.status /= Active then
                Err "Spending is already deleted or replaced"

            else
                validateSpendingTransactions total spendingTransactions
                    |> Result.andThen
                        (\normalizedTransactions ->
                            let
                                replacementSpendingId =
                                    Array.length model.spendings

                                activeTransactions =
                                    getSpendingTransactionsWithIds spendingId model
                                        |> List.filter (\( _, transaction ) -> transaction.status == Active)
                            in
                            buildSpendingMetadata model normalizedTransactions
                                |> Result.andThen
                                    (\metadata ->
                                        let
                                            reconciliation =
                                                reconcileSpendingTransactions activeTransactions normalizedTransactions

                                            keptTransactions =
                                                reconciliation.plannedTransactions
                                                    |> List.filterMap
                                                        (\plannedTransaction ->
                                                            case plannedTransaction of
                                                                KeepTransaction transactionWithId ->
                                                                    Just transactionWithId

                                                                AddTransaction _ ->
                                                                    Nothing
                                                        )

                                            freshTransactions =
                                                reconciliation.plannedTransactions
                                                    |> List.filterMap
                                                        (\plannedTransaction ->
                                                            case plannedTransaction of
                                                                KeepTransaction _ ->
                                                                    Nothing

                                                                AddTransaction transaction ->
                                                                    Just transaction
                                                        )

                                            preparedModel =
                                                let
                                                    replacedModel =
                                                        reconciliation.removedTransactions
                                                            |> List.foldl
                                                                (\( transactionId, _ ) updatedModel ->
                                                                    setTransactionStatus transactionId Replaced updatedModel
                                                                )
                                                                (model |> setSpendingStatus spendingId Replaced)
                                                in
                                                keptTransactions
                                                    |> List.foldl
                                                        (preserveEditedTransaction replacementSpendingId metadata)
                                                        (reconciliation.removedTransactions
                                                            |> List.foldl removeTransactionFromModel replacedModel
                                                        )
                                        in
                                        pendingTransactionsForSpendingWithMetadata replacementSpendingId metadata preparedModel freshTransactions
                                            |> Result.map
                                                (\pendingTransactions ->
                                                    let
                                                        newTransactionIds =
                                                            assignTransactionIds preparedModel pendingTransactions

                                                        finalTransactionIds =
                                                            plannedTransactionIds reconciliation.plannedTransactions newTransactionIds

                                                        spendingWithReplacement =
                                                            { description = description
                                                            , total = total
                                                            , transactionIds = finalTransactionIds
                                                            , status = Active
                                                            }

                                                        modelWithSpending =
                                                            { preparedModel
                                                                | spendings =
                                                                    Array.push spendingWithReplacement preparedModel.spendings
                                                            }
                                                    in
                                                    List.foldl addTransactionToModel modelWithSpending pendingTransactions
                                                )
                                    )
                        )


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


setTransactionStatus : TransactionId -> TransactionStatus -> Model -> Model
setTransactionStatus transactionId status =
    updateTransaction transactionId
        (\transaction ->
            if transaction.status == Active then
                { transaction | status = status }

            else
                transaction
        )


setTransactionStatuses : SpendingId -> TransactionStatus -> Model -> Model
setTransactionStatuses spendingId status model =
    Array.get spendingId model.spendings
        |> Maybe.map
            (.transactionIds
                >> List.foldl
                    (\transactionId updatedModel -> setTransactionStatus transactionId status updatedModel)
                    model
            )
        |> Maybe.withDefault model


updateTransaction : TransactionId -> (Transaction -> Transaction) -> Model -> Model
updateTransaction transactionId transform model =
    updateGroupById transactionId.groupId
        (\group ->
            { group
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
                                                                                        Array.set transactionId.index (transform transaction) day.transactions
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
                        group.years
            }
        )
        model


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


type PlannedTransaction
    = KeepTransaction ( TransactionId, Transaction )
    | AddTransaction SpendingTransaction


type alias SpendingTransactionReconciliation =
    { plannedTransactions : List PlannedTransaction
    , removedTransactions : List ( TransactionId, Transaction )
    }


buildSpendingMetadata : Model -> List SpendingTransaction -> Result String SpendingMetadata
buildSpendingMetadata model transactions =
    let
        groups =
            transactions
                |> List.map .group
    in
    getGroupMembersKey groups model
        |> Result.map
            (\( groupMembersKey, groupMembers ) ->
                { groupMembersKey = groupMembersKey
                , groupMembers = groupMembers
                }
            )


pendingTransactionsForSpendingWithMetadata : SpendingId -> SpendingMetadata -> Model -> List SpendingTransaction -> Result String (List PendingTransaction)
pendingTransactionsForSpendingWithMetadata spendingId metadata model spendingTransactions =
    spendingTransactions
        |> List.map
            (\transaction ->
                groupIdForName model transaction.group
                    |> Result.map (\groupId -> pendingTransactionForSpending spendingId groupId metadata transaction)
            )
        |> List.foldr
            (\result acc ->
                case ( result, acc ) of
                    ( Ok transaction, Ok transactions ) ->
                        Ok (transaction :: transactions)

                    ( Err message, _ ) ->
                        Err message

                    ( _, Err message ) ->
                        Err message
            )
            (Ok [])


type alias ExistingTransactionMatches =
    Dict ComparableSpendingTransaction (List ( TransactionId, Transaction ))


type alias ComparableSpendingTransaction =
    ( NormalizedTransactionKey, Int )


comparableSpendingTransaction : SpendingTransaction -> ComparableSpendingTransaction
comparableSpendingTransaction transaction =
    let
        amountValue =
            case transaction.amount of
                Amount amount ->
                    amount
    in
    ( normalizedTransactionKey transaction, amountValue )


existingTransactionMatches : List ( TransactionId, Transaction ) -> ExistingTransactionMatches
existingTransactionMatches transactions =
    transactions
        |> List.foldl
            (\( transactionId, transaction ) matches ->
                Dict.update
                    (toSpendingTransaction transactionId transaction |> comparableSpendingTransaction)
                    (\maybeMatches ->
                        Just
                            (( transactionId, transaction )
                                :: Maybe.withDefault [] maybeMatches
                            )
                    )
                    matches
            )
            Dict.empty
        |> Dict.map (\_ matches -> List.reverse matches)


takeExistingTransaction :
    SpendingTransaction
    -> ExistingTransactionMatches
    -> ( Maybe ( TransactionId, Transaction ), ExistingTransactionMatches )
takeExistingTransaction spendingTransaction matches =
    case Dict.get (comparableSpendingTransaction spendingTransaction) matches of
        Nothing ->
            ( Nothing, matches )

        Just [] ->
            ( Nothing, Dict.remove (comparableSpendingTransaction spendingTransaction) matches )

        Just (matchedTransaction :: remainingTransactions) ->
            ( Just matchedTransaction
            , if List.isEmpty remainingTransactions then
                Dict.remove (comparableSpendingTransaction spendingTransaction) matches

              else
                Dict.insert (comparableSpendingTransaction spendingTransaction) remainingTransactions matches
            )


reconcileSpendingTransactions :
    List ( TransactionId, Transaction )
    -> List SpendingTransaction
    -> SpendingTransactionReconciliation
reconcileSpendingTransactions existingTransactions spendingTransactions =
    let
        ( plannedTransactions, remainingTransactions ) =
            List.foldl
                (\spendingTransaction ( planned, matches ) ->
                    let
                        ( maybeMatch, updatedMatches ) =
                            takeExistingTransaction spendingTransaction matches
                    in
                    ( case maybeMatch of
                        Just matchedTransaction ->
                            KeepTransaction matchedTransaction :: planned

                        Nothing ->
                            AddTransaction spendingTransaction :: planned
                    , updatedMatches
                    )
                )
                ( [], existingTransactionMatches existingTransactions )
                spendingTransactions
    in
    { plannedTransactions = List.reverse plannedTransactions
    , removedTransactions =
        remainingTransactions
            |> Dict.values
            |> List.concat
    }


plannedTransactionIds : List PlannedTransaction -> List TransactionId -> List TransactionId
plannedTransactionIds plannedTransactions newTransactionIds =
    case plannedTransactions of
        [] ->
            []

        plannedTransaction :: remainingTransactions ->
            case plannedTransaction of
                KeepTransaction ( transactionId, _ ) ->
                    transactionId :: plannedTransactionIds remainingTransactions newTransactionIds

                AddTransaction _ ->
                    case newTransactionIds of
                        [] ->
                            plannedTransactionIds remainingTransactions []

                        transactionId :: remainingIds ->
                            transactionId :: plannedTransactionIds remainingTransactions remainingIds


preserveEditedTransaction : SpendingId -> SpendingMetadata -> ( TransactionId, Transaction ) -> Model -> Model
preserveEditedTransaction replacementSpendingId metadata ( transactionId, transaction ) model =
    let
        updatedTransaction =
            { transaction
                | spendingId = replacementSpendingId
                , groupMembersKey = metadata.groupMembersKey
                , groupMembers = metadata.groupMembers
            }
    in
    model
        |> reassignTransactionMetadata transaction updatedTransaction
        |> updateTransaction transactionId (\_ -> updatedTransaction)


reassignTransactionMetadata : Transaction -> Transaction -> Model -> Model
reassignTransactionMetadata originalTransaction updatedTransaction model =
    if
        originalTransaction.groupMembersKey
            == updatedTransaction.groupMembersKey
            && originalTransaction.groupMembers
            == updatedTransaction.groupMembers
    then
        model

    else
        let
            groupCredits =
                groupCreditsForTransaction originalTransaction
        in
        { model
            | totalGroupCredits =
                model.totalGroupCredits
                    |> addToTotalGroupCredits originalTransaction.groupMembersKey
                        (Dict.map (\_ (Amount amount) -> Amount -amount) groupCredits)
                    |> addToTotalGroupCredits updatedTransaction.groupMembersKey groupCredits
            , persons =
                Dict.map
                    (\_ person ->
                        if Set.member person.name updatedTransaction.groupMembers then
                            { person
                                | belongsTo =
                                    Set.insert updatedTransaction.groupMembersKey person.belongsTo
                            }

                        else
                            person
                    )
                    model.persons
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


groupCreditForTransaction :
    { a | amount : Amount (), side : TransactionSide }
    -> Amount Credit
groupCreditForTransaction transaction =
    case ( transaction.side, transaction.amount ) of
        ( CreditTransaction, Amount amount ) ->
            Amount amount

        ( DebitTransaction, Amount amount ) ->
            Amount -amount


{-| Add a transaction to the model, updating all totals and person belongsTo sets
-}
addTransactionToModel : PendingTransaction -> Model -> Model
addTransactionToModel transaction model =
    let
        groupCredit =
            groupCreditForTransaction transaction

        groupCredits =
            groupCreditsForTransaction transaction
    in
    updateGroupById transaction.groupId
        (\group ->
            { group
                | years =
                    group.years
                        |> Dict.update transaction.year (addTransactionToYear transaction groupCredit >> Just)
                , totalCredit =
                    addAmountToAmount group.totalCredit groupCredit
            }
        )
        { model
            | totalGroupCredits =
                model.totalGroupCredits
                    |> addToTotalGroupCredits transaction.groupMembersKey groupCredits
            , persons =
                Dict.map
                    (\personId person ->
                        if Set.member person.name transaction.groupMembers then
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
        groupCredit =
            groupCreditForTransaction transaction
                |> (\(Amount amount) -> Amount -amount)

        groupCredits =
            groupCreditsForTransaction transaction
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
    in
    updateGroupById transactionId.groupId
        (\group ->
            { group
                | years =
                    group.years
                        |> Dict.update transactionId.year (removeTransactionFromYear transactionId transaction groupCredit)
                , totalCredit =
                    addAmountToAmount group.totalCredit groupCredit
            }
        )
        { model
            | totalGroupCredits =
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
        |> List.sortBy (\( transactionId, _ ) -> ( transactionId.year, transactionId.month, ( transactionId.day, ( transactionId.groupId, transactionId.index ) ) ))
        |> List.map (\( transactionId, transaction ) -> toSpendingTransaction transactionId transaction)


transactionDescription : Spending -> Transaction -> String
transactionDescription spending transaction =
    if String.trim transaction.secondaryDescription == "" then
        spending.description

    else
        spending.description ++ " — " ++ transaction.secondaryDescription


groupTransactionForList :
    Model
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
groupTransactionForList model ( transactionId, transaction ) =
    if transaction.status /= Active then
        Nothing

    else
        Array.get transaction.spendingId model.spendings
            |> Maybe.andThen
                (\spending ->
                    if spending.status /= Active then
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


allTransactionsWithIdsForGroup : GroupId -> StoredGroup -> List ( TransactionId, Transaction )
allTransactionsWithIdsForGroup groupId group =
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
                                        ( { groupId = groupId
                                          , year = year
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
        group.years


allTransactionsWithIds : Model -> List ( TransactionId, Transaction )
allTransactionsWithIds model =
    model.groups
        |> Dict.toList
        |> List.concatMap (\( groupId, group ) -> allTransactionsWithIdsForGroup groupId group)
