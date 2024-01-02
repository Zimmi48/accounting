module Backend exposing (..)

import Basics.Extra exposing (flip)
import Dict exposing (Dict)
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
    case msg of
        NoOpToBackend ->
            ( model, Cmd.none )

        CheckValidName name ->
            ( model
            , if checkValidName model name then
                Cmd.none

              else
                Lamdera.sendToFrontend clientId (NameAlreadyExists name)
            )

        CreatePerson person ->
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

        CreateGroup name members ->
            if checkValidName model name then
                ( { model | groups = Dict.insert name members model.groups }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model
                , Lamdera.sendToFrontend clientId (NameAlreadyExists name)
                )

        CreateSpending { description, year, month, day, total, credits, debits } ->
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

                groupMembersKey =
                    Set.toList groupMembers
                        |> List.filterMap (flip Dict.get model.persons)
                        |> List.map (.id >> String.fromInt)
                        |> String.join ","

                spending =
                    { description = description
                    , day = day
                    , total = total
                    , groupCredits =
                        debits
                            |> Dict.map (\_ (Amount amount) -> Amount -amount)
                            |> addAmounts credits
                    }
            in
            ( { model
                | years =
                    model.years
                        |> Dict.update year (addSpendingToYear month groupMembersKey spending >> Just)
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
            , Lamdera.sendToFrontend clientId OperationSuccessful
            )

        AutocompletePerson prefix ->
            ( model
            , Dict.keys model.persons
                |> autocomplete clientId prefix AutocompletePersonPrefix InvalidPersonPrefix
            )

        AutocompleteGroup prefix ->
            ( model
            , Dict.keys model.groups
                -- persons are automatically single-member groups
                |> (++) (Dict.keys model.persons)
                |> autocomplete clientId prefix AutocompleteGroupPrefix InvalidGroupPrefix
            )

        RequestUserGroupsAndAccounts user ->
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


getGroupMembers model group =
    case Dict.get group model.groups of
        Nothing ->
            -- persons are automatically single-member groups
            Dict.singleton group (Share 1)

        Just members ->
            members


autocomplete clientId prefix autocompleteMsg invalidPrefixMsg list =
    let
        matches =
            List.filter (String.startsWith prefix) list
    in
    case matches of
        [] ->
            Lamdera.sendToFrontend clientId (invalidPrefixMsg prefix)

        [ name ] ->
            Lamdera.sendToFrontend clientId
                (autocompleteMsg
                    { prefix = prefix
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
                        { prefix = prefix
                        , longestCommonPrefix = String.left longestCommonPrefix h
                        , complete = True
                        }
                    )

            else if longestCommonPrefix > String.length prefix then
                Lamdera.sendToFrontend clientId
                    (autocompleteMsg
                        { prefix = prefix
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
    case heads of
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
addToTotalGroupCredits groupMembersKey { groupCredits } =
    Dict.update groupMembersKey
        (Maybe.map (addAmounts groupCredits >> Just)
            >> Maybe.withDefault (Just groupCredits)
        )


addSpendingToYear : Int -> String -> Spending -> Maybe Year -> Year
addSpendingToYear month groupMembersKey spending maybeYear =
    case maybeYear of
        Nothing ->
            { months =
                Dict.singleton month
                    (addSpendingToMonth groupMembersKey spending Nothing)
            , totalGroupCredits =
                Dict.singleton groupMembersKey spending.groupCredits
            }

        Just year ->
            { months =
                year.months
                    |> Dict.update month (addSpendingToMonth groupMembersKey spending >> Just)
            , totalGroupCredits =
                year.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey spending
            }


addSpendingToMonth : String -> Spending -> Maybe Month -> Month
addSpendingToMonth groupMembersKey spending maybeMonth =
    case maybeMonth of
        Nothing ->
            { spendings = [ spending ]
            , totalGroupCredits =
                Dict.singleton groupMembersKey spending.groupCredits
            }

        Just month ->
            { spendings = spending :: month.spendings
            , totalGroupCredits =
                month.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey spending
            }
