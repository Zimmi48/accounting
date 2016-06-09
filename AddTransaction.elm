module AddTransaction exposing (Model, init, Msg, update, view)


import Date exposing (Date)
import Date.Format as Date
import DatePicker exposing (DatePicker, defaultSettings)
import Html exposing (..)
import Html.App as App
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Decode as Decode exposing ((:=))
import Lib exposing (..)
import List.Extra as List
import Maybe
import Maybe.Extra as Maybe
import Positive exposing (Positive)
import String


main : Program Never
main =
  App.program
    { init = init []
    , update =
        (\msg model ->
           let (model, cmd, _) = update msg model in
           (model, cmd)
        )
    , view = view
    , subscriptions = (\_ -> Sub.none)
    }


type alias Model =
  { object : String
  , value : Maybe (Positive Float)
  , valueString : String
  , datePicker : DatePicker
  , date : Maybe Date
  , account : Maybe Account
  , accounts : List Account
  }


init : List Account -> (Model, Cmd Msg)
init accounts =
  let
    (dateModel, dateCmd) =
      DatePicker.init
        { defaultSettings |
          placeholder = "1 Jan 1970"
        , dateFormatter = Date.format "%e %b %Y"
        , firstDayOfWeek = Date.Mon
        , inputClassList = [ ("form-control", True) ]
        , inputName = Just "date"
        }

  in
    { object = ""
    , value = Nothing
    , valueString = ""
    , datePicker = dateModel
    , date = Nothing
    , account = List.head accounts
    , accounts = accounts
    }
  ! [ Cmd.map UpdateDate dateCmd
    ]


type Msg
  = UpdateObject String
  | UpdateValue String
  | UpdateDate DatePicker.Msg
  | UpdateAccount String
  | Submit


update : Msg -> Model -> (Model, Cmd Msg, Maybe Transaction)
update msg model =
  case msg of
    UpdateObject string ->
      ( { model |
          object = String.left 50 string
        }
      , Cmd.none
      , Nothing
      )

    UpdateValue string ->
      ( { model |
          value =
            (String.toFloat string |> Result.toMaybe)
            `Maybe.andThen` Positive.fromNum
        , valueString = string
        }
      , Cmd.none
      , Nothing
      )

    UpdateDate msg ->
      let
        (dateModel, dateCmd, date) =
          DatePicker.update msg model.datePicker
      in
      ( { model |
          datePicker = dateModel
        , date = Maybe.oneOf [date, model.date]
        }
      , Cmd.map UpdateDate dateCmd
      , Nothing
      )

    UpdateAccount s ->
      ( { model |
          account = List.find (\{ name } -> name == s) model.accounts
        }
      , Cmd.none
      , Nothing
      )

    Submit ->
      case (model.value , model.date, model.account) of
        (Just value, Just date, Just account) ->
          if String.isEmpty model.object then
            (model, Cmd.none, Nothing)

          else
            ( model
            , Cmd.none
            , Just
                { object = model.object
                , value = value
                , date = date
                , accountId = account.id
                }
            )

        _ ->
          (model, Cmd.none, Nothing)


view : Model -> Html Msg
view model =
  let
    notready =
      String.isEmpty model.object
      || Maybe.isNothing model.value
      || Maybe.isNothing model.date
      || Maybe.isNothing model.account
  in

  Html.form
    [ onSubmit Submit ]
    [ inputGr "object" "Object" UpdateObject
        [ placeholder "Groceries"
        , value model.object
        , required True
        ]
    , inputGr "value" "Value" UpdateValue
        [ placeholder "23.33"
        , value model.valueString
        , type' "number"
        , Html.Attributes.min "0.01"
        , step "0.01"
        , required True
        ]
    , div
        [ class "form-group" ]
        [ label [ for "date" ] [ text "Date" ]
        , App.map UpdateDate <| DatePicker.view model.datePicker
        ]
    , div
        [ class "form-group" ]
        [ label [ for "account" ] [ text "Account" ]
        , select
            [ name "account"
            , required True
            , class "form-control"
            , on
                "change"
                (Decode.object1 UpdateAccount ("value" := Decode.string)) 
            ]
            (List.indexedMap
               (\i { name , id } ->
                  option
                    [ value id
                    , selected (i == 0)
                    ]
                    [ text name ]
               )
               model.accounts
            )
        ]
    , button
        [ type' "submit"
        , disabled notready
        , classList
            [ ("btn", True)
            , ("btn-success", True)
            ]
        ]
        [ text "Add transaction" ]
    ]




