

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.App as App
import Kinvey exposing (..)
import Login
import LoggedIn


main =
  App.program
     { init = init
     , update = update
     , view = view
     , subscriptions = \_ -> Sub.none
     }


auth : Auth
auth =
  { appId = "kid_ZkL79b5Kbb"
  , appSecret = "aa5f8ad01ed7447fbb9a65fbd8b1f901"
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


update : Msg -> Model -> (Model, Cmd msg)
update msg model =
  case msg of
    NoOp ->
      model ! []


view : Model -> Html msg
view model =
  case model of
    LoginModel model ->
      Login.view model

    LoggedInModel model ->
      LoggedIn.view model




