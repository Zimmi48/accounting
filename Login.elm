module Login exposing (Model, init, view)


import Html exposing (..)
import Html.Attributes exposing (..)


type alias Model =
  { username : String
  , password : String
  }


init : (Model, Cmd msg)
init = Model "" "" ! []


view : Model -> Html msg
view model =
  div []
    [ input [ placeholder "Username" ] []
    , input [ type' "password" , placeholder "Password" ] []
    , button [] [ text "Login" ]
    ]
