module Backend exposing (..)

import Basics.Extra exposing (flip)
import Dict exposing (Dict)
import Env
import Html
import Lamdera exposing (ClientId, SessionId)
import Maybe.Extra as Maybe
import Set exposing (Set)
import Types exposing (..)


type alias Model =
    BackendModel


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

        ( True, CreateSpending { description, year, month, day, total, credits, debits } ) ->
            let
                groupMembersKey =
                    getGroupMembersKey credits debits model

                spending =
                    { description = description
                    , total = total
                    , credits = credits
                    , debits = debits
                    , status = Active
                    }

                updatedModel =
                    addSpendingToModel year month day spending model
            in
            ( updatedModel, Lamdera.sendToFrontend clientId OperationSuccessful )

        ( True, EditTransaction { transactionId, description, year, month, day, total, credits, debits } ) ->
            -- First, validate that the transaction exists and is active
            case findTransaction transactionId model of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (TransactionError "Transaction not found") )

                Just oldTransaction ->
                    if oldTransaction.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (TransactionError "Transaction is already deleted or replaced") )

                    else
                        -- Valid edit: delete old, add new
                        let
                            -- Mark old transaction as replaced
                            updateSpending : Int -> Spending -> Spending
                            updateSpending index spending =
                                if index == transactionId.index then
                                    { spending | status = Replaced }

                                else
                                    spending

                            updateDay : Day -> Day
                            updateDay oldDay =
                                { oldDay | spendings = List.indexedMap updateSpending oldDay.spendings }

                            updateMonth : Month -> Month
                            updateMonth oldMonth =
                                { oldMonth
                                    | days = Dict.update transactionId.day (Maybe.map updateDay) oldMonth.days
                                }

                            updateYear : Year -> Year
                            updateYear oldYear =
                                { oldYear
                                    | months = Dict.update transactionId.month (Maybe.map updateMonth) oldYear.months
                                }

                            -- Create new spending
                            newSpending =
                                { description = description
                                , total = total
                                , credits = credits
                                , debits = debits
                                , status = Active
                                }

                            -- Step 1: Remove old transaction from totals
                            modelWithReplaced =
                                { model
                                    | years = Dict.update transactionId.year (Maybe.map updateYear) model.years
                                }
                                    |> removeSpendingFromModel transactionId oldTransaction

                            -- Step 2: Add new transaction
                            finalModel =
                                addSpendingToModel year month day newSpending modelWithReplaced
                        in
                        ( finalModel, Lamdera.sendToFrontend clientId OperationSuccessful )

        ( True, DeleteTransaction transactionId ) ->
            -- First, validate that the transaction exists and is active
            case findTransaction transactionId model of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (TransactionError "Transaction not found") )

                Just transaction ->
                    if transaction.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (TransactionError "Transaction is already deleted or replaced") )

                    else
                        -- Valid delete: mark as deleted and remove from totals
                        let
                            updateSpending : Int -> Spending -> Spending
                            updateSpending index spending =
                                if index == transactionId.index then
                                    { spending | status = Deleted }

                                else
                                    spending

                            updateDay : Day -> Day
                            updateDay day =
                                { day | spendings = List.indexedMap updateSpending day.spendings }

                            updateMonth : Month -> Month
                            updateMonth month =
                                { month
                                    | days = Dict.update transactionId.day (Maybe.map updateDay) month.days
                                }

                            updateYear : Year -> Year
                            updateYear year =
                                { year
                                    | months = Dict.update transactionId.month (Maybe.map updateMonth) year.months
                                }

                            -- Mark transaction as deleted
                            modelWithDeleted =
                                { model
                                    | years = Dict.update transactionId.year (Maybe.map updateYear) model.years
                                }

                            -- Remove from totals
                            finalModel =
                                removeSpendingFromModel transactionId transaction modelWithDeleted
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

        ( True, RequestTransactionDetails transactionId ) ->
            case findTransaction transactionId model of
                Nothing ->
                    ( model, Lamdera.sendToFrontend clientId (TransactionError "Transaction not found") )

                Just transaction ->
                    if transaction.status /= Active then
                        ( model, Lamdera.sendToFrontend clientId (TransactionError "Transaction is not active") )

                    else
                        ( model
                        , Lamdera.sendToFrontend clientId
                            (TransactionDetails
                                { transactionId = transactionId
                                , description = transaction.description
                                , year = transactionId.year
                                , month = transactionId.month
                                , day = transactionId.day
                                , total = transaction.total
                                , credits = transaction.credits
                                , debits = transaction.debits
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
                        (\year { months } accYears ->
                            Dict.foldr
                                (\month { days } accMonths ->
                                    Dict.foldr
                                        (\day { spendings } accDays ->
                                            List.indexedMap
                                                (\index spending ->
                                                    if spending.status == Active then
                                                        -- Look for the group in both credits and debits
                                                        case ( Dict.get group spending.credits, Dict.get group spending.debits ) of
                                                            ( Just credit, Nothing ) ->
                                                                Just
                                                                    { transactionId =
                                                                        { year = year
                                                                        , month = month
                                                                        , day = day
                                                                        , index = index
                                                                        }
                                                                    , description = spending.description
                                                                    , year = year
                                                                    , month = month
                                                                    , day = day
                                                                    , total = (\(Amount a) -> Amount a) spending.total
                                                                    , share = toDebit credit
                                                                    }

                                                            ( Nothing, Just debit ) ->
                                                                Just
                                                                    { transactionId =
                                                                        { year = year
                                                                        , month = month
                                                                        , day = day
                                                                        , index = index
                                                                        }
                                                                    , description = spending.description
                                                                    , year = year
                                                                    , month = month
                                                                    , day = day
                                                                    , total = (\(Amount a) -> Amount a) spending.total
                                                                    , share = debit
                                                                    }

                                                            ( Just credit, Just debit ) ->
                                                                Just
                                                                    { transactionId =
                                                                        { year = year
                                                                        , month = month
                                                                        , day = day
                                                                        , index = index
                                                                        }
                                                                    , description = spending.description
                                                                    , year = year
                                                                    , month = month
                                                                    , day = day
                                                                    , total = (\(Amount a) -> Amount a) spending.total
                                                                    , share = addAmountToAmount (toDebit credit) debit
                                                                    }

                                                            ( Nothing, Nothing ) ->
                                                                Nothing

                                                    else
                                                        Nothing
                                                )
                                                spendings
                                                |> List.filterMap identity
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
                |> encodeToString
                |> JsonExport
                |> Lamdera.sendToFrontend clientId
            )

        ( True, ImportJson json ) ->
            case decodeString json of
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
    -> Spending
    -> Dict String (Dict String (Amount Credit))
    -> Dict String (Dict String (Amount Credit))
addToTotalGroupCredits groupMembersKey { credits, debits } =
    let
        -- Convert debits to negative credits for aggregation
        groupCredits =
            debits
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
                |> addAmounts credits
    in
    Dict.update groupMembersKey
        (Maybe.map (addAmounts groupCredits >> Just)
            >> Maybe.withDefault (Just groupCredits)
        )


addSpendingToYear : Int -> Int -> String -> Spending -> Maybe Year -> Year
addSpendingToYear month day groupMembersKey spending maybeYear =
    let
        -- Convert debits to negative credits for aggregation
        groupCredits =
            spending.debits
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
                |> addAmounts spending.credits
    in
    case maybeYear of
        Nothing ->
            { months =
                Dict.singleton month
                    (addSpendingToMonth day groupMembersKey spending Nothing)
            , totalGroupCredits =
                Dict.singleton groupMembersKey groupCredits
            }

        Just year ->
            { months =
                year.months
                    |> Dict.update month (addSpendingToMonth day groupMembersKey spending >> Just)
            , totalGroupCredits =
                year.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey spending
            }


addSpendingToMonth : Int -> String -> Spending -> Maybe Month -> Month
addSpendingToMonth day groupMembersKey spending maybeMonth =
    let
        -- Convert debits to negative credits for aggregation
        groupCredits =
            spending.debits
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
                |> addAmounts spending.credits
    in
    case maybeMonth of
        Nothing ->
            { days =
                Dict.singleton day
                    (addSpendingToDay groupMembersKey spending Nothing)
            , totalGroupCredits =
                Dict.singleton groupMembersKey groupCredits
            }

        Just month ->
            { days =
                month.days
                    |> Dict.update day (addSpendingToDay groupMembersKey spending >> Just)
            , totalGroupCredits =
                month.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey spending
            }


addSpendingToDay : String -> Spending -> Maybe Day -> Day
addSpendingToDay groupMembersKey spending maybeDay =
    let
        -- Convert debits to negative credits for aggregation
        groupCredits =
            spending.debits
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
                |> addAmounts spending.credits
    in
    case maybeDay of
        Nothing ->
            { spendings = [ spending ]
            , totalGroupCredits =
                Dict.singleton groupMembersKey groupCredits
            }

        Just day ->
            { spendings = spending :: day.spendings
            , totalGroupCredits =
                day.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey spending
            }


{-| Remove spending amount from the hierarchy totals. Used for deletes and edits.
-}
removeSpendingFromYear : Int -> Int -> String -> Spending -> Maybe Year -> Maybe Year
removeSpendingFromYear month day groupMembersKey spending maybeYear =
    case maybeYear of
        Nothing ->
            Nothing

        Just year ->
            let
                updatedMonths =
                    year.months
                        |> Dict.update month (removeSpendingFromMonth day groupMembersKey spending)

                updatedTotalGroupCredits =
                    year.totalGroupCredits
                        |> addToTotalGroupCredits groupMembersKey (negateSpending spending)
            in
            Just
                { months = updatedMonths
                , totalGroupCredits = updatedTotalGroupCredits
                }


removeSpendingFromMonth : Int -> String -> Spending -> Maybe Month -> Maybe Month
removeSpendingFromMonth day groupMembersKey spending maybeMonth =
    case maybeMonth of
        Nothing ->
            Nothing

        Just month ->
            let
                updatedDays =
                    month.days
                        |> Dict.update day (removeSpendingFromDay groupMembersKey spending)

                updatedTotalGroupCredits =
                    month.totalGroupCredits
                        |> addToTotalGroupCredits groupMembersKey (negateSpending spending)
            in
            Just
                { days = updatedDays
                , totalGroupCredits = updatedTotalGroupCredits
                }


removeSpendingFromDay : String -> Spending -> Maybe Day -> Maybe Day
removeSpendingFromDay groupMembersKey spending maybeDay =
    case maybeDay of
        Nothing ->
            Nothing

        Just day ->
            let
                updatedTotalGroupCredits =
                    day.totalGroupCredits
                        |> addToTotalGroupCredits groupMembersKey (negateSpending spending)
            in
            Just
                { spendings = day.spendings
                , totalGroupCredits = updatedTotalGroupCredits
                }


{-| Create a negative version of a spending for subtraction
-}
negateSpending : Spending -> Spending
negateSpending spending =
    { spending
        | total = (\(Amount a) -> Amount -a) spending.total
        , credits = Dict.map (\_ (Amount a) -> Amount -a) spending.credits
        , debits = Dict.map (\_ (Amount a) -> Amount -a) spending.debits
    }


{-| Find a specific transaction by ID
-}
findTransaction : TransactionId -> Model -> Maybe Spending
findTransaction transactionId model =
    model.years
        |> Dict.get transactionId.year
        |> Maybe.andThen (.months >> Dict.get transactionId.month)
        |> Maybe.andThen (.days >> Dict.get transactionId.day)
        |> Maybe.andThen (.spendings >> List.drop transactionId.index >> List.head)


{-| Get group members key for a spending
-}
getGroupMembersKey : Dict String (Amount Credit) -> Dict String (Amount Debit) -> Model -> String
getGroupMembersKey credits debits model =
    let
        groupMembers =
            (Dict.keys credits ++ Dict.keys debits)
                |> List.map
                    (\group ->
                        Dict.get group model.groups
                            |> Maybe.map Dict.keys
                            |> Maybe.withDefault [ group ]
                    )
                |> List.concat
                |> Set.fromList
    in
    Set.toList groupMembers
        |> List.filterMap (flip Dict.get model.persons)
        |> List.map (.id >> String.fromInt)
        |> String.join ","


{-| Get group members key for an existing spending
-}
getGroupMembersKeyForSpending spending model =
    let
        groupMembers =
            (Dict.keys spending.credits ++ Dict.keys spending.debits)
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


{-| Add a spending to the model, updating all totals and person belongsTo sets
-}
addSpendingToModel : Int -> Int -> Int -> Spending -> Model -> Model
addSpendingToModel year month day spending model =
    let
        ( groupMembersKey, groupMembers ) =
            getGroupMembersKeyForSpending spending model
    in
    { model
        | years =
            model.years
                |> Dict.update year (addSpendingToYear month day groupMembersKey spending >> Just)
        , totalGroupCredits =
            model.totalGroupCredits
                |> addToTotalGroupCredits groupMembersKey spending
        , persons =
            Dict.map
                (\name person ->
                    if Set.member name groupMembers then
                        { person
                            | belongsTo =
                                Set.insert groupMembersKey person.belongsTo
                        }

                    else
                        person
                )
                model.persons
    }


{-| Remove a spending from the model totals (but keep the spending record marked as deleted)
-}
removeSpendingFromModel : TransactionId -> Spending -> Model -> Model
removeSpendingFromModel transactionId spending model =
    let
        ( groupMembersKey, groupMembers ) =
            getGroupMembersKeyForSpending spending model
    in
    { model
        | years =
            model.years
                |> Dict.update transactionId.year (removeSpendingFromYear transactionId.month transactionId.day groupMembersKey spending)
        , totalGroupCredits =
            model.totalGroupCredits
                |> addToTotalGroupCredits groupMembersKey (negateSpending spending)
    }
