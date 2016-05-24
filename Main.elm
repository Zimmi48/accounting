port module Main exposing (..)


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.App as App
import Kinvey exposing (Session)
import Login
import LoggedIn


-- TODO: if session is invalid, go back to Login page


main : Program (Maybe Session)
main =
  App.programWithFlags
     { init = init
     , update = update
     , view = view
     , subscriptions = \_ -> Sub.none
     }


port setStorage : Session -> Cmd msg


type Model
  = LoginModel Login.Model
  | LoggedInModel LoggedIn.Model


init : Maybe Session -> (Model, Cmd Msg)
init savedSession =
  case savedSession of
    Nothing ->
      let (model, cmd) = Login.init in
      LoginModel model ! [ cmd ]

    Just session ->
      initLoggedIn session


initLoggedIn : Session -> (Model, Cmd Msg)
initLoggedIn session =
  let (model, cmd) = LoggedIn.init session in
  LoggedInModel model !
    [ Cmd.map LoggedInMsg cmd
    , setStorage session
    ]


type Msg
  = NoOp
  | LoginMsg Login.Msg
  | LoggedInMsg LoggedIn.Msg
  | NewSession Session


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case ( msg , model ) of
    ( LoginMsg msg , LoginModel model ) ->
      let (model, cmd) = Login.update NewSession LoginMsg msg model in
      ( LoginModel model , cmd )

    ( NewSession session , _ ) ->
      initLoggedIn session

    ( LoggedInMsg msg , LoggedInModel model ) ->
      let (model, cmd) = LoggedIn.update msg model in
      ( LoggedInModel model , Cmd.map LoggedInMsg cmd )

    _ ->
      model ! []


view : Model -> Html Msg
view model =
  case model of
    LoginModel model ->
      App.map LoginMsg <| Login.view model

    LoggedInModel model ->
      App.map LoggedInMsg <| LoggedIn.view model




