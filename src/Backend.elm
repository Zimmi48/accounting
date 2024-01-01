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
                        |> Dict.update year (addSpendingToYear month spending >> Just)
                , totalGroupCredits =
                    addToAllTotalGroupSpendings spending.groupCredits model.totalGroupCredits
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
            let
                groups =
                    model.groups
                        |> Dict.filter (\_ members -> Dict.member user members)
                        |> Dict.toList
                        |> (::) ( user, Dict.singleton user (Share 1) )

                groupsWithAmounts =
                    groups
                        |> List.map
                            (\( name, group ) ->
                                ( name
                                , group
                                , model.totalGroupCredits
                                    |> Dict.get name
                                    |> Maybe.andThen (Dict.get name)
                                    |> Maybe.withDefault (Amount 0)
                                )
                            )

                debitorsWithAmounts =
                    groupsWithAmounts
                        |> List.filter (\( _, _, Amount amount ) -> amount < 0)

                creditorsWithAmounts =
                    groupsWithAmounts
                        |> List.filter (\( _, _, Amount amount ) -> amount > 0)
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


addSpendingToYear : Int -> Spending -> Maybe Year -> Year
addSpendingToYear month spending maybeYear =
    case maybeYear of
        Nothing ->
            { months = Dict.singleton month (addSpendingToMonth spending Nothing)
            , totalGroupCredits = addToAllTotalGroupSpendings spending.groupCredits Dict.empty
            }

        Just year ->
            { months = Dict.update month (addSpendingToMonth spending >> Just) year.months
            , totalGroupCredits = addToAllTotalGroupSpendings spending.groupCredits year.totalGroupCredits
            }


addSpendingToMonth : Spending -> Maybe Month -> Month
addSpendingToMonth spending maybeMonth =
    case maybeMonth of
        Nothing ->
            { spendings = [ spending ]
            , totalGroupCredits = addToAllTotalGroupSpendings spending.groupCredits Dict.empty
            }

        Just month ->
            { spendings = spending :: month.spendings
            , totalGroupCredits = addToAllTotalGroupSpendings spending.groupCredits month.totalGroupCredits
            }
