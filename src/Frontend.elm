module Frontend exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest(..))
import Browser.Dom exposing (getViewport)
import Browser.Events exposing (onResize)
import Browser.Navigation as Nav
import Date
import DatePicker
import Dialog
import Dict exposing (Dict)
import Dict.Extra as Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Font as Font
import Element.Input as Input
import Html exposing (Html)
import Html.Attributes as Attr
import Html.Events exposing (..)
import Lamdera
import List.Extra as List
import Maybe.Extra as Maybe
import Regex
import String
import Task
import Tuple exposing (..)
import Types exposing (..)
import Url


type alias Model =
    FrontendModel


app =
    Lamdera.frontend
        { init = init
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = \_ -> onResize ViewportChanged
        , view = view
        }


init : Url.Url -> Nav.Key -> ( Model, Cmd FrontendMsg )
init url key =
    let
        ( page, routingCmds ) =
            routing url
    in
    ( { page = page
      , showDialog = Just (PasswordDialog { password = "", submitted = False })
      , user = ""
      , nameValidity = Incomplete
      , userGroups = Nothing
      , group = ""
      , groupValidity = Incomplete
      , groupTransactions = []
      , key = key
      , windowWidth = 1000
      , windowHeight = 1000
      }
    , Cmd.batch
        [ routingCmds
        , Task.perform
            (\viewport ->
                ViewportChanged
                    (round viewport.viewport.width)
                    (round viewport.viewport.height)
            )
            getViewport
        ]
    )


routing : Url.Url -> ( Page, Cmd FrontendMsg )
routing url =
    case url.path of
        "/" ->
            ( Home, Cmd.none )

        "/json" ->
            ( Json Nothing, Lamdera.sendToBackend RequestAllTransactions )

        "/import" ->
            ( Import "", Cmd.none )

        _ ->
            ( NotFound, Cmd.none )


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    let
                        ( page, routingCmds ) =
                            routing url
                    in
                    ( { model | page = page }
                    , Cmd.batch
                        [ Nav.pushUrl model.key (Url.toString url)
                        , routingCmds
                        ]
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            let
                ( page, routingCmds ) =
                    routing url
            in
            ( { model | page = page }
            , routingCmds
            )

        NoOpFrontendMsg ->
            ( model, Cmd.none )

        ShowAddPersonDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddPersonDialog
                            { name = ""
                            , nameInvalid = False
                            , submitted = False
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddGroupDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddGroupDialog
                            { name = ""
                            , nameInvalid = False
                            , members = []
                            , submitted = False
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddSpendingDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddSpendingDialog
                            { description = ""
                            , date = Nothing
                            , dateText = ""
                            , datePickerModel = DatePicker.init
                            , total = ""
                            , credits = []
                            , debits = []
                            , submitted = False
                            }
                        )
              }
            , Task.perform SetToday Date.today
            )

        SetToday today ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | datePickerModel = DatePicker.setToday today dialogModel.datePickerModel
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        Submit ->
            case model.page of
                Import "" ->
                    ( model, Cmd.none )

                Import json ->
                    ( model
                    , Lamdera.sendToBackend (ImportJson json)
                    )

                Home ->
                    case model.showDialog of
                        Just (AddPersonDialog dialogModel) ->
                            ( { model | showDialog = Just (AddPersonDialog { dialogModel | submitted = True }) }
                            , Lamdera.sendToBackend (CreatePerson dialogModel.name)
                            )

                        Just (AddGroupDialog dialogModel) ->
                            let
                                members =
                                    dialogModel.members
                                        |> List.map
                                            (\( member, share, _ ) ->
                                                ( member
                                                , share
                                                    |> String.toInt
                                                    |> Maybe.withDefault 0
                                                )
                                            )
                                        |> Dict.fromListDedupe (+)
                                        |> Dict.map (\_ -> Share)
                            in
                            ( { model | showDialog = Just (AddGroupDialog { dialogModel | submitted = True }) }
                            , Lamdera.sendToBackend (CreateGroup dialogModel.name members)
                            )

                        Just (AddSpendingDialog dialogModel) ->
                            let
                                credits =
                                    dialogModel.credits
                                        |> List.map
                                            (\( group, amount, _ ) ->
                                                ( group
                                                , amount
                                                    |> parseAmountValue
                                                    |> Maybe.withDefault 0
                                                )
                                            )
                                        |> Dict.fromListDedupe (+)
                                        |> Dict.map (\_ -> Amount)

                                debits =
                                    dialogModel.debits
                                        |> List.map
                                            (\( group, amount, _ ) ->
                                                ( group
                                                , amount
                                                    |> parseAmountValue
                                                    |> Maybe.withDefault 0
                                                )
                                            )
                                        |> Dict.fromListDedupe (+)
                                        |> Dict.map (\_ -> Amount)
                            in
                            case
                                ( dialogModel.date
                                , parseAmountValue dialogModel.total
                                )
                            of
                                ( Just date, Just total ) ->
                                    ( { model
                                        | showDialog =
                                            Just
                                                (AddSpendingDialog
                                                    { dialogModel | submitted = True }
                                                )
                                      }
                                    , Lamdera.sendToBackend
                                        (CreateSpending
                                            { description = dialogModel.description
                                            , year = Date.year date
                                            , month = Date.monthNumber date
                                            , day = Date.day date
                                            , total = Amount total
                                            , credits = credits
                                            , debits = debits
                                            }
                                        )
                                    )

                                _ ->
                                    ( model, Cmd.none )

                        Just (PasswordDialog dialogModel) ->
                            ( { model
                                | showDialog =
                                    Just
                                        (PasswordDialog
                                            { dialogModel | submitted = True }
                                        )
                              }
                            , Lamdera.sendToBackend (CheckPassword dialogModel.password)
                            )

                        Nothing ->
                            ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        Cancel ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

        UpdateName name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = name, nameInvalid = False }) }
                        , Lamdera.sendToBackend (CheckValidName name)
                        )

                Just (AddGroupDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddGroupDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddGroupDialog { dialogModel | name = name, nameInvalid = False }) }
                        , Lamdera.sendToBackend (CheckValidName name)
                        )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | description = name }) }
                    , Cmd.none
                    )

                Just (PasswordDialog dialogModel) ->
                    ( model, Cmd.none )

                Nothing ->
                    ( { model
                        | user = name
                        , nameValidity = Incomplete
                        , userGroups = Nothing
                      }
                    , if String.length name > 0 then
                        Lamdera.sendToBackend (AutocompletePerson name)

                      else
                        Cmd.none
                    )

        UpdateGroupName name ->
            ( { model
                | group = name
                , groupValidity = Incomplete
                , groupTransactions = []
              }
            , if String.length name > 0 then
                Lamdera.sendToBackend (AutocompleteGroup name)

              else
                Cmd.none
            )

        AddMember member ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> addNameInList member "1"
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompletePerson member)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateMember index member ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> updateNameInList
                                                    index
                                                    member
                                                    (\_ -> "1")
                                    }
                                )
                      }
                    , if String.length member > 0 then
                        Lamdera.sendToBackend (AutocompletePerson member)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateShare index share ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> updateValueInList index share
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateTotal total ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | total = total }) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ChangeDatePicker changeEvent ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (case changeEvent of
                                        DatePicker.DateChanged date ->
                                            { dialogModel | date = Just date, dateText = Date.toIsoString date }

                                        DatePicker.TextChanged dateText ->
                                            { dialogModel
                                                | date =
                                                    Date.fromIsoString dateText
                                                        |> Result.toMaybe
                                                , dateText = dateText
                                            }

                                        DatePicker.PickerChanged subMsg ->
                                            { dialogModel | datePickerModel = DatePicker.update subMsg dialogModel.datePickerModel }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AddCreditor group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | credits =
                                            dialogModel.credits
                                                |> addGroup dialogModel group
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompleteGroup group)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateCreditor index group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | credits =
                                            dialogModel.credits
                                                |> updateNameInList
                                                    index
                                                    group
                                                    (computeRemainder dialogModel)
                                    }
                                )
                      }
                    , if String.length group > 0 then
                        Lamdera.sendToBackend (AutocompleteGroup group)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateCredit index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | credits =
                                            dialogModel.credits
                                                |> updateValueInList index amount
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AddDebitor group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | debits =
                                            dialogModel.debits
                                                |> addGroup dialogModel group
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompleteGroup group)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateDebitor index group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | debits =
                                            dialogModel.debits
                                                |> updateNameInList
                                                    index
                                                    group
                                                    (computeRemainder dialogModel)
                                    }
                                )
                      }
                    , if String.length group > 0 then
                        Lamdera.sendToBackend (AutocompleteGroup group)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateDebit index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | debits =
                                            dialogModel.debits
                                                |> updateValueInList index amount
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdatePassword password ->
            case model.showDialog of
                Just (PasswordDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (PasswordDialog
                                    { dialogModel | password = password }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateJson json ->
            case model.page of
                Import _ ->
                    ( { model | page = Import json }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ViewportChanged width height ->
            ( { model
                | windowWidth = width
                , windowHeight = height
              }
            , Cmd.none
            )


computeRemainder { total } list =
    ((total
        |> parseAmountValue
        |> Maybe.withDefault 0
     )
        - (list
            |> List.filterMap (\( _, amount, _ ) -> amount |> parseAmountValue)
            |> List.sum
          )
    )
        |> viewAmount


addGroup model name list =
    addNameInList name (computeRemainder model list) list


addNameInList name defaultValue list =
    ( name, defaultValue, Incomplete ) :: list


updateNameInList index name computeDefaultValue list =
    if index == 0 && name == "" then
        case list of
            [] ->
                []

            ( _, value, _ ) :: tail ->
                if value == "" || value == computeDefaultValue tail then
                    tail

                else
                    ( name, value, Incomplete ) :: tail

    else
        list
            |> List.updateAt index
                (\( _, value, _ ) ->
                    ( name, value, Incomplete )
                )


updateValueInList index value list =
    if index == 0 && value == "" then
        case list of
            [] ->
                []

            ( name, _, nameValidity ) :: tail ->
                if name == "" then
                    tail

                else
                    ( name, value, nameValidity ) :: tail

    else
        list
            |> List.updateAt index
                (\( name, _, nameValidity ) ->
                    ( name, value, nameValidity )
                )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )

        OperationSuccessful ->
            case model.page of
                Import _ ->
                    ( { model | page = Import "" }
                    , Cmd.none
                    )

                Home ->
                    ( { model | showDialog = Nothing }
                    , (++)
                        (if model.nameValidity == Complete then
                            [ Lamdera.sendToBackend (RequestUserGroups model.user) ]

                         else
                            []
                        )
                        (if model.groupValidity == Complete then
                            [ Lamdera.sendToBackend (RequestGroupTransactions model.group) ]

                         else
                            []
                        )
                        |> Cmd.batch
                    )

                _ ->
                    ( model, Cmd.none )

        NameAlreadyExists name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    if dialogModel.name == name then
                        -- we reset submitted to False because this can be
                        -- an error message we get from the backend in case
                        -- of a race creating this person
                        ( { model
                            | showDialog =
                                Just
                                    (AddPersonDialog
                                        { dialogModel
                                            | nameInvalid = True
                                            , submitted = False
                                        }
                                    )
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                Just (AddGroupDialog dialogModel) ->
                    if dialogModel.name == name then
                        -- we reset submitted to False because this can be
                        -- an error message we get from the backend in case
                        -- of a race creating this group
                        ( { model
                            | showDialog =
                                Just
                                    (AddGroupDialog
                                        { dialogModel
                                            | nameInvalid = True
                                            , submitted = False
                                        }
                                    )
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        InvalidPersonPrefix prefix ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> markInvalidPrefix prefix
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( if String.startsWith prefix model.user then
                        { model | nameValidity = InvalidPrefix }

                      else
                        model
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AutocompletePersonPrefix response ->
            case model.showDialog of
                Just (AddGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddGroupDialog
                                    { dialogModel
                                        | members =
                                            dialogModel.members
                                                |> completeToLongestCommonPrefix response
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    let
                        userLower =
                            String.toLower model.user
                    in
                    if
                        String.startsWith response.prefixLower userLower
                            && String.startsWith userLower (String.toLower response.longestCommonPrefix)
                    then
                        ( { model
                            | user = response.longestCommonPrefix
                            , nameValidity =
                                if response.complete then
                                    Complete

                                else
                                    Incomplete
                          }
                        , if response.complete then
                            Lamdera.sendToBackend
                                (RequestUserGroups response.longestCommonPrefix)

                          else
                            Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        InvalidGroupPrefix prefix ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | credits =
                                            dialogModel.credits
                                                |> markInvalidPrefix prefix
                                        , debits =
                                            dialogModel.debits
                                                |> markInvalidPrefix prefix
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Just _ ->
                    ( model, Cmd.none )

                Nothing ->
                    ( if String.startsWith prefix model.group then
                        { model | groupValidity = InvalidPrefix }

                      else
                        model
                    , Cmd.none
                    )

        AutocompleteGroupPrefix response ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | credits =
                                            dialogModel.credits
                                                |> completeToLongestCommonPrefix response
                                        , debits =
                                            dialogModel.debits
                                                |> completeToLongestCommonPrefix response
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Just _ ->
                    ( model, Cmd.none )

                Nothing ->
                    let
                        groupLower =
                            String.toLower model.group
                    in
                    if
                        String.startsWith response.prefixLower groupLower
                            && String.startsWith groupLower (String.toLower response.longestCommonPrefix)
                    then
                        ( { model
                            | group = response.longestCommonPrefix
                            , groupValidity =
                                if response.complete then
                                    Complete

                                else
                                    Incomplete
                          }
                        , if response.complete then
                            Lamdera.sendToBackend
                                (RequestGroupTransactions response.longestCommonPrefix)

                          else
                            Cmd.none
                        )

                    else
                        ( model, Cmd.none )

        ListUserGroups { user, debitors, creditors } ->
            ( if model.user == user then
                { model
                    | userGroups =
                        Just
                            { debitors = debitors
                            , creditors = creditors
                            }
                }

              else
                model
            , Cmd.none
            )

        ListGroupTransactions { group, transactions } ->
            ( if model.group == group then
                { model
                    | groupTransactions =
                        transactions
                }

              else
                model
            , Cmd.none
            )

        JsonExport json ->
            case model.page of
                Json _ ->
                    ( { model | page = Json (Just json) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )


markInvalidPrefix prefix list =
    list
        |> List.map
            (\( name, value, nameValidity ) ->
                if String.startsWith prefix name then
                    ( name, value, InvalidPrefix )

                else
                    ( name, value, nameValidity )
            )


completeToLongestCommonPrefix { prefixLower, longestCommonPrefix, complete } list =
    list
        |> List.map
            (\( name, value, nameValidity ) ->
                let
                    n =
                        String.toLower name
                in
                if
                    String.startsWith prefixLower n
                        && String.startsWith n (String.toLower longestCommonPrefix)
                then
                    ( longestCommonPrefix
                    , value
                    , if complete then
                        Complete

                      else
                        Incomplete
                    )

                else
                    ( name, value, nameValidity )
            )


view : Model -> Browser.Document FrontendMsg
view model =
    case model.page of
        NotFound ->
            { title = "Accounting - Not Found"
            , body =
                [ layout []
                    (column [ centerX, padding 20, spacing 20 ]
                        [ row [] [ text "Page not found" ]
                        , row []
                            [ link
                                [ mouseOver [ Font.color (rgb255 255 0 0) ]
                                , Font.underline
                                ]
                                { label = text "Return home", url = "/" }
                            ]
                        ]
                    )
                ]
            }

        Json json ->
            { title = "Accounting - JSON"
            , body =
                [ layout
                    [ centerX
                    , padding 50
                    ]
                    (column
                        [ shrink |> maximum (model.windowHeight * 9 // 10) |> height
                        , scrollbarY
                        , Border.solid
                        , Border.rounded 5
                        , Border.width 1
                        , padding 5
                        ]
                        [ paragraph
                            []
                            [ case json of
                                Just jsonString ->
                                    el
                                        [ Font.family [ Font.monospace ]
                                        , Font.size 14
                                        , height fill
                                        ]
                                        (text jsonString)

                                Nothing ->
                                    text "Waiting to receive JSON export"
                            ]
                        ]
                    )
                ]
            }

        Import json ->
            { title = "Accounting - Import"
            , body =
                [ layout []
                    (column [ padding 20, spacing 20, width fill ]
                        [ el [ centerX ] (text "Import JSON")
                        , Input.multiline
                            [ width fill
                            , px (model.windowHeight * 8 // 10) |> height
                            , Font.family [ Font.monospace ]
                            , Font.size 14
                            ]
                            { text = json
                            , placeholder = Just (Input.placeholder [] (text "Paste JSON here"))
                            , onChange = UpdateJson
                            , label = Input.labelHidden "JSON"
                            , spellcheck = False
                            }
                        , el [ centerX ]
                            (Input.button greenButtonStyle
                                { label = text "Import"
                                , onPress =
                                    if String.length json > 0 then
                                        Just Submit

                                    else
                                        Nothing
                                }
                            )
                        ]
                    )
                ]
            }

        Home ->
            let
                config title inputs canSubmit =
                    { closeMessage = Just Cancel
                    , maskAttributes = []
                    , containerAttributes =
                        [ Background.color (rgb 1 1 1)
                        , Border.solid
                        , Border.rounded 5
                        , Border.width 1
                        , centerX
                        , centerY
                        , shrink |> maximum (model.windowHeight * 9 // 10) |> height
                        , scrollbarY
                        ]
                    , headerAttributes =
                        [ padding 20
                        , Background.color green
                        ]
                    , bodyAttributes =
                        [ padding 20
                        , height fill
                        ]
                    , footerAttributes =
                        [ Border.widthEach { top = 1, bottom = 0, left = 0, right = 0 }
                        , Border.solid
                        ]
                    , header = Just (text title)
                    , body =
                        Just
                            (column [ spacing 20 ]
                                inputs
                            )
                    , footer =
                        Just
                            (row [ centerX, spacing 20, padding 20, alignRight ]
                                [ Input.button redButtonStyle
                                    { label = text "Cancel"
                                    , onPress = Just Cancel
                                    }
                                , Input.button
                                    (if canSubmit then
                                        greenButtonStyle

                                     else
                                        grayButtonStyle
                                    )
                                    { label = text "Submit"
                                    , onPress =
                                        if canSubmit then
                                            Just Submit

                                        else
                                            Nothing
                                    }
                                ]
                            )
                    }

                dialogConfig =
                    model.showDialog
                        |> Maybe.map
                            (\dialog ->
                                case dialog of
                                    AddPersonDialog dialogModel ->
                                        config "Add Person"
                                            (nameInput model.windowWidth dialogModel)
                                            (canSubmitPerson dialogModel)

                                    AddGroupDialog dialogModel ->
                                        let
                                            label =
                                                "Add Group / Account"
                                        in
                                        config label
                                            (addGroupInputs model.windowWidth dialogModel)
                                            (canSubmitGroup dialogModel)

                                    AddSpendingDialog dialogModel ->
                                        config "Add Spending"
                                            (addSpendingInputs model.windowWidth dialogModel)
                                            (canSubmitSpending dialogModel)

                                    PasswordDialog dialogModel ->
                                        config "Password"
                                            [ Input.currentPassword []
                                                { label = labelStyle model.windowWidth "Password"
                                                , placeholder = Nothing
                                                , onChange = UpdatePassword
                                                , text = dialogModel.password
                                                , show = False
                                                }
                                            ]
                                            (String.length dialogModel.password > 0)
                            )

                textFieldAttributes field =
                    case field model of
                        InvalidPrefix ->
                            [ Background.color red ]

                        _ ->
                            []
            in
            { title = "Accounting"
            , body =
                -- Elm UI body
                [ layout
                    [ inFront (Dialog.view dialogConfig)
                    ]
                    (column [ width fill, spacing 20, padding 20 ]
                        ([ (if model.windowWidth > 650 then
                                row [ centerX, spacing 70, padding 20 ]

                            else
                                column [ centerX, spacing 20, padding 20 ]
                           )
                            [ Input.button greenButtonStyle
                                { label = text "Add Person"
                                , onPress = Just ShowAddPersonDialog
                                }
                            , Input.button greenButtonStyle
                                { label = text "Add Group / Account"
                                , onPress = Just ShowAddGroupDialog
                                }
                            , Input.button greenButtonStyle
                                { label = text "Add Spending"
                                , onPress = Just ShowAddSpendingDialog
                                }
                            ]
                         , Input.text (textFieldAttributes .nameValidity)
                            { label = labelStyle model.windowWidth "Your name:"
                            , placeholder = Nothing
                            , onChange = UpdateName
                            , text = model.user
                            }
                         ]
                            ++ (case model.userGroups of
                                    Just { debitors, creditors } ->
                                        [ row [ width fill, spaceEvenly, padding 20 ]
                                            [ column [ spacing 10, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
                                                [ text "Your Debitor Groups / Accounts"
                                                , viewGroups model.user debitors
                                                ]
                                            , column [ spacing 10, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
                                                [ text "Your Creditor Groups / Accounts"
                                                , viewGroups model.user creditors
                                                ]
                                            , column [ spacing 10, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
                                                [ text "Amounts due"
                                                , personalAmountsDue debitors creditors
                                                    |> Dict.toList
                                                    |> viewAmountsDue
                                                ]
                                            ]
                                        ]

                                    _ ->
                                        []
                               )
                            ++ [ Input.text (textFieldAttributes .groupValidity)
                                    { label = labelStyle model.windowWidth "Display transactions for group / account:"
                                    , placeholder = Nothing
                                    , onChange = UpdateGroupName
                                    , text = model.group
                                    }
                               ]
                            ++ List.map viewTransaction model.groupTransactions
                        )
                    )
                ]
            }


labelStyle windowWidth textValue =
    if windowWidth > 650 then
        Input.labelLeft [] (text textValue)

    else
        Input.labelAbove [] (Element.paragraph [] [ text textValue ])


buttonStyle =
    [ spaceEvenly
    , padding 10
    , Border.solid
    , Border.rounded 5
    , Border.width 1
    ]


greenButtonStyle =
    buttonStyle ++ [ Background.color green ]


green =
    rgb255 152 251 152


redButtonStyle =
    buttonStyle ++ [ Background.color red ]


red =
    rgb 1 0.5 0.5


grayButtonStyle =
    buttonStyle ++ [ Background.color (rgb 0.8 0.8 0.8) ]


nameInput windowWidth { name, nameInvalid } =
    let
        attributes =
            if nameInvalid then
                [ Background.color red ]

            else
                []
    in
    [ Input.text attributes
        { label = labelStyle windowWidth "Name"
        , placeholder = Nothing
        , onChange = UpdateName
        , text = name
        }
    ]


addGroupInputs windowWidth ({ members } as model) =
    let
        nbMembers =
            List.length members
    in
    nameInput windowWidth model
        ++ listInputs
            windowWidth
            "Owner"
            "Share"
            AddMember
            UpdateMember
            UpdateShare
            members


addSpendingInputs windowWidth { description, date, dateText, datePickerModel, total, credits, debits } =
    [ Input.text []
        { label = labelStyle windowWidth "Description"
        , placeholder = Nothing
        , onChange = UpdateName
        , text = description
        }
    , DatePicker.input []
        { label = labelStyle windowWidth "Date"
        , placeholder = Nothing
        , onChange = ChangeDatePicker
        , selected = date
        , text = dateText
        , settings = DatePicker.defaultSettings
        , model = datePickerModel
        }
    , Input.text []
        { label = labelStyle windowWidth "Total"
        , placeholder = Nothing
        , onChange = UpdateTotal
        , text = total
        }
    , column [ spacing 20, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
        ([ text "Debitors" ]
            ++ listInputs
                windowWidth
                "Debitor"
                "Amount"
                AddDebitor
                UpdateDebitor
                UpdateDebit
                debits
        )
    , column [ spacing 20, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
        ([ text "Creditors (payers)" ]
            ++ listInputs
                windowWidth
                "Creditor"
                "Amount"
                AddCreditor
                UpdateCreditor
                UpdateCredit
                credits
        )
    ]


listInputs windowWidth nameLabel valueLabel addMsg updateNameMsg updateValueMsg items =
    let
        listSize =
            List.length items
    in
    (if List.all (\( name, _, _ ) -> String.length name > 0) items then
        [ row [ spacing 20 ]
            [ Input.text []
                { label =
                    labelStyle windowWidth
                        (nameLabel
                            ++ " "
                            ++ (listSize + 1 |> String.fromInt)
                        )
                , placeholder = Nothing
                , onChange = addMsg
                , text = ""
                }
            , Input.text []
                { label = labelStyle windowWidth valueLabel
                , placeholder = Nothing
                , onChange = \_ -> NoOpFrontendMsg
                , text = ""
                }
            ]
        ]

     else
        []
    )
        ++ List.indexedMap
            (\index ( name, value, nameValidity ) ->
                let
                    attributes =
                        case nameValidity of
                            InvalidPrefix ->
                                [ Background.color red ]

                            _ ->
                                []
                in
                row [ spacing 20 ]
                    [ Input.text attributes
                        { label =
                            labelStyle windowWidth
                                (nameLabel
                                    ++ " "
                                    ++ (listSize - index |> String.fromInt)
                                )
                        , placeholder = Nothing
                        , onChange = updateNameMsg index
                        , text = name
                        }
                    , Input.text []
                        { label = labelStyle windowWidth valueLabel
                        , placeholder = Nothing
                        , onChange = updateValueMsg index
                        , text = value
                        }
                    ]
            )
            items
        |> List.reverse


canSubmitPerson { name, nameInvalid, submitted } =
    not submitted && not nameInvalid && String.length name > 0


canSubmitGroup { name, nameInvalid, members, submitted } =
    not submitted
        && not nameInvalid
        && String.length name
        > 0
        && (members
                |> List.map
                    (\( _, share, nameValidity ) ->
                        case nameValidity of
                            Complete ->
                                String.toInt share

                            _ ->
                                Nothing
                    )
                |> Maybe.combine
                |> Maybe.map (List.sum >> (\sum -> sum > 0))
                |> Maybe.withDefault False
           )


canSubmitSpending { description, date, total, credits, debits, submitted } =
    not submitted
        && Maybe.isJust date
        && String.length description
        > 0
        && (total
                |> parseAmountValue
                |> Maybe.andThen
                    (\totalInt ->
                        Maybe.combine
                            [ credits
                                |> List.map
                                    (\( _, amount, nameValidity ) ->
                                        case nameValidity of
                                            Complete ->
                                                parseAmountValue amount

                                            _ ->
                                                Nothing
                                    )
                                |> Maybe.combine
                                |> Maybe.map List.sum
                                |> Maybe.map ((==) totalInt)
                            , debits
                                |> List.map
                                    (\( _, amount, nameValidity ) ->
                                        case nameValidity of
                                            Complete ->
                                                parseAmountValue amount

                                            _ ->
                                                Nothing
                                    )
                                |> Maybe.combine
                                |> Maybe.map List.sum
                                |> Maybe.map ((==) totalInt)
                            ]
                    )
                |> Maybe.map (List.all identity)
                |> Maybe.withDefault False
           )


viewTransaction transaction =
    row [ spacing 20, padding 20, Background.color (rgb 0.9 0.9 0.9) ]
        [ String.fromInt transaction.year ++ "-" ++ String.fromInt transaction.month ++ "-" ++ String.fromInt transaction.day |> text
        , transaction.description |> text
        , transaction.share |> (\(Amount amount) -> amount) |> viewAmount |> text
        , "(Total: " ++ (transaction.total |> (\(Amount amount) -> amount) |> viewAmount) ++ ")" |> text
        ]


viewGroups : String -> List ( String, Group, Amount a ) -> Element FrontendMsg
viewGroups user list =
    let
        preprocessedList =
            list
                |> List.map
                    (\( name, shares, Amount totalAmount ) ->
                        let
                            userShare =
                                Dict.get user shares
                                    |> Maybe.map (\(Share share) -> share)
                                    |> Maybe.withDefault 0

                            totalShares =
                                Dict.values shares
                                    |> List.map (\(Share share) -> share)
                                    |> List.sum

                            userAmount =
                                totalAmount * userShare // totalShares
                        in
                        { name = name
                        , share =
                            String.fromInt userShare
                                ++ " out of "
                                ++ String.fromInt totalShares
                        , totalAmount = viewAmount totalAmount
                        , userAmount = userAmount
                        }
                    )

        total =
            preprocessedList
                |> List.map .userAmount
                |> List.sum
                |> (\totalUserAmount ->
                        [ { name = "Total"
                          , share = ""
                          , totalAmount = ""
                          , userAmount = totalUserAmount
                          }
                        ]
                   )
    in
    table [ Border.solid, Border.width 1, padding 20, spacing 30 ]
        { data = preprocessedList ++ total
        , columns =
            [ { header = text "Name"
              , width = fill
              , view = .name >> text
              }
            , { header = text "Your share"
              , width = fill
              , view = .share >> text
              }
            , { header = text "Total spending"
              , width = fill
              , view = .totalAmount >> text
              }
            , { header = text "Your spending"
              , width = fill
              , view = .userAmount >> viewAmount >> text
              }
            ]
        }


viewAmountsDue : List ( String, Amount Debit ) -> Element FrontendMsg
viewAmountsDue data =
    table [ Border.solid, Border.width 1, padding 20, spacing 30 ]
        { data = data
        , columns =
            [ { header = text "Name"
              , width = fill
              , view = first >> text
              }
            , { header = text "Due"
              , width = fill
              , view =
                    second
                        >> (\(Amount value) -> max 0 value)
                        >> viewAmount
                        >> text
              }
            , { header = text "Owed"
              , width = fill
              , view =
                    second
                        >> (\(Amount value) -> min 0 value)
                        >> negate
                        >> viewAmount
                        >> text
              }
            ]
        }


viewAmount amount =
    let
        sign =
            if amount < 0 then
                "-"

            else
                ""

        absAmount =
            abs amount
    in
    remainderBy 100 absAmount
        |> String.fromInt
        |> String.padLeft 2 '0'
        |> (++) "."
        |> (++) (absAmount // 100 |> String.fromInt)
        |> (++) sign


parseAmountValue : String -> Maybe Int
parseAmountValue amount =
    case
        Regex.fromString "^(\\-?)([0-9]*)[.,]?([0-9]*)$"
            |> Maybe.withDefault Regex.never
            |> flip Regex.find amount
            |> List.map .submatches
    of
        [ [ Nothing, Just integer, Nothing ] ] ->
            String.toInt integer
                |> Maybe.map ((*) 100)

        [ [ Just "-", Just integer, Nothing ] ] ->
            String.toInt integer
                |> Maybe.map ((*) -100)

        [ [ Nothing, Nothing, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt decimal
                        |> Maybe.map ((*) 10)

                2 ->
                    String.toInt decimal

                _ ->
                    Nothing

        [ [ Just "-", Nothing, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt decimal
                        |> Maybe.map ((*) -10)

                2 ->
                    String.toInt decimal
                        |> Maybe.map negate

                _ ->
                    Nothing

        [ [ Nothing, Just integer, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((*) 10)
                                    |> Maybe.map ((+) integerValue)
                            )

                2 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((+) integerValue)
                            )

                _ ->
                    Nothing

        [ [ Just "-", Just integer, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((*) 10)
                                    |> Maybe.map ((+) integerValue)
                            )
                        |> Maybe.map negate

                2 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((+) integerValue)
                            )
                        |> Maybe.map negate

                _ ->
                    Nothing

        _ ->
            Nothing


personalAmounts : List ( String, Group, Amount a ) -> Dict String (Amount a)
personalAmounts list =
    list
        |> List.map
            (\( _, shares, Amount totalAmount ) ->
                let
                    totalShares =
                        Dict.values shares
                            |> List.map (\(Share share) -> share)
                            |> List.sum
                in
                Dict.map
                    (\_ (Share share) ->
                        Amount (totalAmount * share // totalShares)
                    )
                    shares
            )
        |> List.foldl addAmounts Dict.empty


personalAmountsDue : List ( String, Group, Amount Debit ) -> List ( String, Group, Amount Credit ) -> Dict String (Amount Debit)
personalAmountsDue debitorGroups creditorGroups =
    let
        debits =
            personalAmounts debitorGroups

        credits =
            personalAmounts creditorGroups
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
    in
    addAmounts debits credits
