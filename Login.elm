module Login exposing (Model, init, view, update, Msg, UpdateResponse(..))


import Http
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Task
import Kinvey exposing (Session)
import MyKinvey exposing (..)


-- TODO : handle Enter key


type alias Model =
  { username : String
  , password : String
  , recentError : String
  }


init : (Model, Cmd msg)
init = Model "" "" "" ! []


view : Model -> Html Msg
view model =
  Html.form
    [ class "form-inline"
    , onSubmit Login
    ]
    [ legend [] [ text "Please login" ]
    , div
        [ class "form-group" ]
        [ label
            [ for "email"
            , class "sr-only"
            ]
            [ text "Email" ]
        , input
            [ onInput Username
            , type' "email"
            , placeholder "Email"
            , value model.username
            , name "email"
            , required True
            , class "form-control"
            ] []
        ]
    , text " " -- for spacing
    , div
        [ class "form-group" ]
        [ label
            [ for "password"
            , class "sr-only"
            ]
            [ text "Password" ]
        , input
            [ onInput Password
            , type' "password"
            , placeholder "Password"
            , value model.password
            , name "password"
            , required True
            , class "form-control"
            ] []
        ]
    , text " " -- for spacing
    , button
        [ type' "submit"
        , classList
            [ ("btn", True)
            , ("btn-default", True)
            ]
        ] [ text "Login" ]
    , div
        [ class "text-danger" ]
        [ text model.recentError ]
    ]


type Msg
  = Username String
  | Password String
  | Login
  | Error Kinvey.Error
  | Success Session


type UpdateResponse
  = Update (Model, Cmd Msg)
  | NewSession Session


update : Msg -> Model -> UpdateResponse
update msg model =
  case msg of
    Username s ->
      Update ( { model | username = s } , Cmd.none )

    Password s ->
      Update ( { model | password = s } , Cmd.none )

    Login ->
      Update
        ( Debug.log "Login" model
        , Task.perform Error Success
            <| login model.username model.password
        )

    Error e ->
      Update
        ( { model |
            recentError =
              case e of
                Kinvey.HttpError (Http.BadResponse 401 _) ->
                  "Authentication failure"

                _ ->
                  Kinvey.errorToString e
          }
        , Cmd.none
        )

    Success session ->
      NewSession session
