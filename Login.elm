module Login exposing (Model, init, view, update, Msg)


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Task
import Kinvey exposing (Session)
import MyKinvey exposing (..)


type alias Model =
  { username : String
  , password : String
  }


init : (Model, Cmd msg)
init = Model "" "" ! []


view : Model -> Html Msg
view model =
  div []
    [ input
        [ onInput Username
        , placeholder "Username"
        , value model.username
        ] []
    , input
        [ onInput Password
        , type' "password"
        , placeholder "Password"
        , value model.password
        ] []
    , button [ onClick Login ] [ text "Login" ]
    ]


type Msg
  = Username String
  | Password String
  | Login
  | Error Kinvey.Error


update : (Session -> msg) -> (Msg -> msg) -> Msg -> Model -> (Model, Cmd msg)
update successMsg mapMsg msg model =
  case msg of
    Username s ->
      { model | username = s } ! []

    Password s ->
      { model | password = s } ! []

    Login ->
      model
        ! [ Task.perform (mapMsg << Error) successMsg
              <| login model.username model.password ]

    _ ->
      init
