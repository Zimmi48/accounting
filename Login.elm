module Login exposing (Model, init, view, update, Msg)


import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)


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
        ] []
    , input
        [ onInput Password
        , type' "password"
        , placeholder "Password"
        ] []
    , button [ onClick Login ] [ text "Login" ]
    ]


type Msg
  = Username String
  | Password String
  | Login


update : Msg -> Model -> (Model, Cmd msg)
update msg model =
  case msg of
    Username s ->
      { model | username = s } ! []

    Password s ->
      { model | password = s } ! []

    Login ->
      model ! []
