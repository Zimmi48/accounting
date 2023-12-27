module Backend exposing (..)

import Basics.Extra exposing (flip)
import Dict exposing (Dict)
import Html
import Lamdera exposing (ClientId, SessionId)
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
      , accounts = Dict.empty
      , persons = Set.empty
      }
    , Cmd.none
    )


update : BackendMsg -> Model -> ( Model, Cmd BackendMsg )
update msg model =
    case msg of
        NoOpBackendMsg ->
            ( model, Cmd.none )



-- Warning: currently, this function does not check that the account or group does not already exist before possibly overwriting it.
-- Warning: currently, this function does not check that all the persons in the account or group are already in the persons set.


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
            ( { model | persons = Set.insert person model.persons }
            , Lamdera.sendToFrontend clientId OperationSuccessful
            )

        AddAccount name owners ->
            ( { model | accounts = Dict.insert name owners model.accounts }
            , Lamdera.sendToFrontend clientId OperationSuccessful
            )

        AddGroup name members ->
            ( { model | groups = Dict.insert name members model.groups }
            , Lamdera.sendToFrontend clientId OperationSuccessful
            )

        AddSpending description year month day amount groupSpendings transactions ->
            let
                spending =
                    { description = description
                    , day = day
                    , totalSpending = amount
                    , groupSpendings = groupSpendings
                    , transactions = transactions
                    }
            in
            ( { model
                | years =
                    model.years
                        |> Dict.update year (addSpendingToYear month spending >> Just)
              }
            , Lamdera.sendToFrontend clientId OperationSuccessful
            )

        AutocompletePerson prefix ->
            let
                matches =
                    Set.filter (\name -> String.startsWith prefix name) model.persons
                        |> Set.toList
            in
            ( model
            , case matches of
                [] ->
                    Lamdera.sendToFrontend clientId (InvalidPersonPrefix prefix)

                [ name ] ->
                    Lamdera.sendToFrontend clientId (UniquePersonPrefix prefix name)

                _ ->
                    if List.member prefix matches then
                        Lamdera.sendToFrontend clientId (CompleteNotUniquePerson prefix)

                    else
                        Cmd.none
            )

        AutocompleteGroup prefix ->
            let
                matches =
                    Dict.filter (\name _ -> String.startsWith prefix name) model.groups
                        |> Dict.keys
            in
            ( model
            , case matches of
                [] ->
                    Lamdera.sendToFrontend clientId (InvalidGroupPrefix prefix)

                [ name ] ->
                    Lamdera.sendToFrontend clientId (UniqueGroupPrefix prefix name)

                _ ->
                    if List.member prefix matches then
                        Lamdera.sendToFrontend clientId (CompleteNotUniqueGroup prefix)

                    else
                        Cmd.none
            )

        AutocompleteAccount prefix ->
            let
                matches =
                    Dict.filter (\name _ -> String.startsWith prefix name) model.accounts
                        |> Dict.keys
            in
            ( model
            , case matches of
                [] ->
                    Lamdera.sendToFrontend clientId (InvalidAccountPrefix prefix)

                [ name ] ->
                    Lamdera.sendToFrontend clientId (UniqueAccountPrefix prefix name)

                _ ->
                    if List.member prefix matches then
                        Lamdera.sendToFrontend clientId (CompleteNotUniqueAccount prefix)

                    else
                        Cmd.none
            )


checkValidName : Model -> String -> Bool
checkValidName model name =
    String.length name > 0
    && not (Set.member name model.persons)
    && not (Dict.member name model.groups)
    && not (Dict.member name model.accounts)


addSpendingToYear : Int -> Spending -> Maybe Year -> Year
addSpendingToYear month spending maybeYear =
    case maybeYear of
        Nothing ->
            { months =
                Dict.singleton month (addSpendingToMonth spending Nothing)
            , totalGroupSpendings = spending.groupSpendings
            , totalAccountTransactions = spending.transactions
            }

        Just year ->
            { months =
                year.months
                    |> Dict.update month (addSpendingToMonth spending >> Just)
            , totalGroupSpendings =
                spending.groupSpendings
                    |> flip Dict.foldl
                        year.totalGroupSpendings
                        (\key (Amount value) totalGroupSpendings ->
                            Dict.update key (addAmount value) totalGroupSpendings
                        )
            , totalAccountTransactions =
                spending.transactions
                    |> flip Dict.foldl
                        year.totalAccountTransactions
                        (\key (Amount value) totalAccountTransactions ->
                            Dict.update key (addAmount value) totalAccountTransactions
                        )
            }


addSpendingToMonth : Spending -> Maybe Month -> Month
addSpendingToMonth spending maybeMonth =
    case maybeMonth of
        Nothing ->
            { spendings = [ spending ]
            , totalGroupSpendings = spending.groupSpendings
            , totalAccountTransactions = spending.transactions
            }

        Just month ->
            { spendings = spending :: month.spendings
            , totalGroupSpendings =
                spending.groupSpendings
                    |> flip Dict.foldl
                        month.totalGroupSpendings
                        (\key (Amount value) groupSpendings ->
                            Dict.update key (addAmount value) groupSpendings
                        )
            , totalAccountTransactions =
                spending.transactions
                    |> flip Dict.foldl
                        month.totalAccountTransactions
                        (\key (Amount value) transactions ->
                            Dict.update key (addAmount value) transactions
                        )
            }


addAmount : Int -> Maybe Amount -> Maybe Amount
addAmount value maybeAmount =
    case maybeAmount of
        Nothing ->
            Just (Amount value)

        Just (Amount amount) ->
            Just (Amount (amount + value))
