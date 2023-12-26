module Backend exposing (..)

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

        CheckNoPerson name ->
            ( model
            , if Set.member name model.persons then
                Lamdera.sendToFrontend clientId (PersonAlreadyExists name)

              else
                Cmd.none
            )

        CheckNoAccount name ->
            ( model
            , if Dict.member name model.accounts then
                Lamdera.sendToFrontend clientId (AccountAlreadyExists name)

              else
                Cmd.none
            )

        CheckNoGroup name ->
            ( model
            , if Dict.member name model.groups then
                Lamdera.sendToFrontend clientId (GroupAlreadyExists name)

              else
                Cmd.none
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
