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
      , totalGroupSpendings = Dict.empty
      , accounts = Dict.empty
      , totalAccountTransactions = Dict.empty
      , persons = Set.empty
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

        AddPerson person ->
            if checkValidName model person then
                ( { model | persons = Set.insert person model.persons }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model
                , Lamdera.sendToFrontend clientId (NameAlreadyExists person)
                )

        AddGroup name members ->
            if checkValidName model name then
                ( { model | groups = Dict.insert name members model.groups }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model
                , Lamdera.sendToFrontend clientId (NameAlreadyExists name)
                )

        AddAccount name owners ->
            if checkValidName model name then
                ( { model | accounts = Dict.insert name owners model.accounts }
                , Lamdera.sendToFrontend clientId OperationSuccessful
                )

            else
                ( model
                , Lamdera.sendToFrontend clientId (NameAlreadyExists name)
                )

        AddSpending { description, year, month, day, totalSpending, groupSpendings, transactions } ->
            let
                spending =
                    { description = description
                    , day = day
                    , totalSpending = totalSpending
                    , groupSpendings = groupSpendings
                    , transactions = transactions
                    }
            in
            ( { model
                | years =
                    model.years
                        |> Dict.update year (addSpendingToYear month spending >> Just)
            , totalGroupSpendings = addToAllTotalGroupSpendings  spending model.totalGroupSpendings
            , totalAccountTransactions = addToAllTotalAccountTransactions  spending model.totalAccountTransactions
              }
            , Lamdera.sendToFrontend clientId OperationSuccessful
            )

        AutocompletePerson prefix ->
            ( model
            , Set.toList model.persons
                |> autocomplete clientId prefix AutocompletePersonPrefix InvalidPersonPrefix
            )

        AutocompleteGroup prefix ->
            ( model
            , Dict.keys model.groups
                -- persons are automatically single-member groups
                |> (++) (Set.toList model.persons)
                |> autocomplete clientId prefix AutocompleteGroupPrefix InvalidGroupPrefix
            )

        AutocompleteAccount prefix ->
            ( model
            , Dict.keys model.accounts
                -- persons are automatically single-owner accounts
                |> (++) (Set.toList model.persons)
                |> autocomplete clientId prefix AutocompleteAccountPrefix InvalidAccountPrefix
            )

        RequestUserGroupsAndAccounts user ->
            let
                groups =
                    Dict.toList model.groups ++ List.map (\person -> (person, Dict.singleton person (Share 1))) (Set.toList model.persons)
                        -- |> Dict.filter (\_ members -> Dict.member user members)
                        -- |> Dict.toList
                        -- |> (::) ( user, Dict.singleton user (Share 1) )

                accounts =
                    Dict.toList model.accounts ++ List.map (\person -> (person, Dict.singleton person (Share 1))) (Set.toList model.persons)
                        -- |> Dict.filter (\_ owners -> Dict.member user owners)
                        -- |> Dict.toList
                        -- |> (::) ( user, Dict.singleton user (Share 1) )

                groupsWithAmounts =
                    groups
                        |> List.map
                            (\( name, group ) ->
                                ( name
                                , group
                                , model.totalGroupSpendings
                                    |> Dict.get name
                                    |> Maybe.andThen (.groupAmounts >> Dict.get name)
                                    |> Maybe.withDefault (Amount 0)
                                )
                            )

                accountsWithAmounts =
                    accounts
                        |> List.map
                            (\( name, group ) ->
                                ( name
                                , group
                                , model.totalAccountTransactions
                                    |> Dict.get name
                                    |> Maybe.andThen (.accountAmounts >> Dict.get name)
                                    |> Maybe.withDefault (Amount 0)
                                )
                            )
            in
            ( model
            , Lamdera.sendToFrontend clientId
                (ListUserGroupsAndAccounts
                    { user = user
                    , groups = groupsWithAmounts
                    , accounts = accountsWithAmounts
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
                    (AutocompleteAccountPrefix
                        { prefix = prefix
                        , longestCommonPrefix = String.left longestCommonPrefix h
                        , complete = True
                        }
                    )

            else if longestCommonPrefix > String.length prefix then
                Lamdera.sendToFrontend clientId
                    (AutocompleteAccountPrefix
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
        && not (Set.member name model.persons)
        && not (Dict.member name model.groups)
        && not (Dict.member name model.accounts)


addSpendingToYear : Int -> Spending -> Maybe Year -> Year
addSpendingToYear month spending maybeYear =
    case maybeYear of
        Nothing ->
            { months = Dict.singleton month (addSpendingToMonth spending Nothing)
            , totalGroupSpendings = addToAllTotalGroupSpendings  spending Dict.empty
            , totalAccountTransactions = addToAllTotalAccountTransactions  spending Dict.empty
            }

        Just year ->
            { months = Dict.update month (addSpendingToMonth spending >> Just) year.months
            , totalGroupSpendings = addToAllTotalGroupSpendings  spending year.totalGroupSpendings 
            , totalAccountTransactions = addToAllTotalAccountTransactions  spending year.totalAccountTransactions 
            }


addSpendingToMonth : Spending -> Maybe Month -> Month
addSpendingToMonth spending maybeMonth =
    case maybeMonth of
        Nothing ->
            { spendings = [ spending ]
            , totalGroupSpendings = addToAllTotalGroupSpendings  spending Dict.empty
            , totalAccountTransactions = addToAllTotalAccountTransactions  spending Dict.empty
            }

        Just month ->
            { spendings = spending :: month.spendings
            , totalGroupSpendings = addToAllTotalGroupSpendings  spending month.totalGroupSpendings
            , totalAccountTransactions = addToAllTotalAccountTransactions  spending month.totalAccountTransactions
            }
