

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.App as App
import Kinvey exposing (Session)
import Login
import LoggedIn


main =
  App.program
     { init = init
     , update = update
     , view = view
     , subscriptions = \_ -> Sub.none
     }


type Model
  = LoginModel Login.Model
  | LoggedInModel LoggedIn.Model


init : (Model, Cmd msg)
init =
  let (model, cmd) = Login.init in
  LoginModel model ! [ cmd ]


type Msg
  = NoOp
  | LoginMsg Login.Msg
  | NewSession Session


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case (msg , model) of
    (LoginMsg msg , LoginModel model) ->
      let (model, cmd) = Login.update NewSession LoginMsg msg model in
      ( LoginModel model , cmd )

    _ ->
      model ! []


view : Model -> Html Msg
view model =
  case model of
    LoginModel model ->
      App.map LoginMsg <| Login.view model

    LoggedInModel model ->
      LoggedIn.view model




