module Test.Herald.Git (tests) where

import Data.Text (Text)
import Data.Text qualified as T

import Hedgehog (Property, (===))
import Hedgehog.Extras qualified as H
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (testProperty)

import Herald.Git (normaliseGitRepo, parseRepoSlug)
import Herald.Git.Repository (lookupGitConfig)

tests :: TestTree
tests =
  testGroup
    "Herald.Git"
    [ testGroup
        "parseRepoSlug"
        [ testProperty "SSH URL" prop_slug_ssh
        , testProperty "SSH URL without .git" prop_slug_ssh_no_git
        , testProperty "HTTPS URL" prop_slug_https
        , testProperty "HTTPS URL without .git" prop_slug_https_no_git
        , testProperty "unrecognised URL returns Nothing" prop_slug_unknown
        , testProperty "SSH without colon returns Nothing" prop_slug_ssh_no_colon
        , testProperty "HTTPS with no path returns Nothing" prop_slug_https_no_path
        , testProperty "SSH with slash instead of colon returns Nothing" prop_slug_ssh_slash
        ]
    , testGroup
        "normaliseGitRepo"
        [ testProperty "bare slug assumes GitHub" prop_normalise_bare_slug
        , testProperty "HTTPS URL passes through" prop_normalise_https
        , testProperty "SSH URL gets normalised" prop_normalise_ssh
        , testProperty "trailing slash stripped" prop_normalise_trailing_slash
        , testProperty "unrecognised text passes through" prop_normalise_unknown
        ]
    , testGroup
        "lookupGitConfig"
        [ testProperty "simple section.key" prop_simple_key
        , testProperty "subsection key" prop_subsection_key
        , testProperty "missing key" prop_missing_key
        , testProperty "missing section" prop_missing_section
        , testProperty "case insensitive section" prop_case_insensitive
        , testProperty "subsection name is case sensitive" prop_subsection_case_sensitive
        , testProperty "comment lines ignored" prop_comments_ignored
        , testProperty "multiple sections" prop_multiple_sections
        ]
    ]

-- | SSH git@host:owner/repo.git -> https://host/owner/repo
prop_slug_ssh :: Property
prop_slug_ssh =
  H.propertyOnce $
    parseRepoSlug "git@github.com:IntersectMBO/cardano-api.git"
      === Just "https://github.com/IntersectMBO/cardano-api"

-- | SSH without .git suffix
prop_slug_ssh_no_git :: Property
prop_slug_ssh_no_git =
  H.propertyOnce $
    parseRepoSlug "git@gitlab.com:myorg/myrepo"
      === Just "https://gitlab.com/myorg/myrepo"

-- | HTTPS https://host/owner/repo.git -> https://host/owner/repo
prop_slug_https :: Property
prop_slug_https =
  H.propertyOnce $
    parseRepoSlug "https://github.com/IntersectMBO/cardano-api.git"
      === Just "https://github.com/IntersectMBO/cardano-api"

-- | HTTPS without .git suffix
prop_slug_https_no_git :: Property
prop_slug_https_no_git =
  H.propertyOnce $
    parseRepoSlug "https://github.com/MyOrg/my-repo"
      === Just "https://github.com/MyOrg/my-repo"

-- | Unrecognised URL scheme returns Nothing
prop_slug_unknown :: Property
prop_slug_unknown =
  H.propertyOnce $
    parseRepoSlug "svn://example.com/repo" === Nothing

-- | SSH URL without a colon (no host:path separator)
prop_slug_ssh_no_colon :: Property
prop_slug_ssh_no_colon =
  H.propertyOnce $
    parseRepoSlug "git@github.com" === Nothing

-- | HTTPS URL with only a host and no owner/repo path
prop_slug_https_no_path :: Property
prop_slug_https_no_path =
  H.propertyOnce $
    parseRepoSlug "https://github.com" === Nothing

-- | SSH-style URL with slash instead of colon (ssh:// form)
prop_slug_ssh_slash :: Property
prop_slug_ssh_slash =
  H.propertyOnce $
    parseRepoSlug "git@github.com/owner/repo.git" === Nothing

-- normaliseGitRepo tests

-- | Bare owner/repo slug is expanded to a GitHub HTTPS URL
prop_normalise_bare_slug :: Property
prop_normalise_bare_slug =
  H.propertyOnce $
    normaliseGitRepo "IntersectMBO/cardano-api"
      === "https://github.com/IntersectMBO/cardano-api"

-- | Full HTTPS URL passes through unchanged
prop_normalise_https :: Property
prop_normalise_https =
  H.propertyOnce $
    normaliseGitRepo "https://github.com/IntersectMBO/cardano-api"
      === "https://github.com/IntersectMBO/cardano-api"

-- | SSH URL is converted to HTTPS
prop_normalise_ssh :: Property
prop_normalise_ssh =
  H.propertyOnce $
    normaliseGitRepo "git@github.com:IntersectMBO/cardano-api.git"
      === "https://github.com/IntersectMBO/cardano-api"

-- | Trailing slash is stripped
prop_normalise_trailing_slash :: Property
prop_normalise_trailing_slash =
  H.propertyOnce $
    normaliseGitRepo "https://github.com/IntersectMBO/cardano-api/"
      === "https://github.com/IntersectMBO/cardano-api"

-- | Unrecognised text passes through unchanged
prop_normalise_unknown :: Property
prop_normalise_unknown =
  H.propertyOnce $
    normaliseGitRepo "just-a-word" === "just-a-word"

sampleConfig :: Text
sampleConfig =
  T.unlines
    [ "[core]"
    , "\tbare = false"
    , "\trepositoryformatversion = 0"
    , "[remote \"origin\"]"
    , "\turl = git@github.com:IntersectMBO/cardano-api.git"
    , "\tfetch = +refs/heads/*:refs/remotes/origin/*"
    , "[user]"
    , "\temail = mateusz@iohk.io"
    , "\tname = Mateusz Galazyn"
    , "[github]"
    , "\tuser = mgalazyn"
    , "[scriv]"
    , "\tuser-nick = mg"
    , "# a comment line"
    , "; another comment"
    ]

-- | Simple section.key lookups return the expected values.
prop_simple_key :: Property
prop_simple_key = H.propertyOnce $ do
  lookupGitConfig "user.email" sampleConfig === Just "mateusz@iohk.io"
  lookupGitConfig "github.user" sampleConfig === Just "mgalazyn"
  lookupGitConfig "scriv.user-nick" sampleConfig === Just "mg"
  lookupGitConfig "core.bare" sampleConfig === Just "false"

-- | Subsection keys like remote.origin.url are resolved correctly.
prop_subsection_key :: Property
prop_subsection_key = H.propertyOnce $ do
  lookupGitConfig "remote.origin.url" sampleConfig
    === Just "git@github.com:IntersectMBO/cardano-api.git"
  lookupGitConfig "remote.origin.fetch" sampleConfig
    === Just "+refs/heads/*:refs/remotes/origin/*"

-- | A key that doesn't exist in an existing section returns Nothing.
prop_missing_key :: Property
prop_missing_key = H.propertyOnce $ do
  lookupGitConfig "user.nonexistent" sampleConfig === Nothing

-- | A section that doesn't exist returns Nothing.
prop_missing_section :: Property
prop_missing_section = H.propertyOnce $ do
  lookupGitConfig "nonexistent.key" sampleConfig === Nothing

-- | Section and key lookups are case-insensitive.
prop_case_insensitive :: Property
prop_case_insensitive = H.propertyOnce $ do
  lookupGitConfig "USER.EMAIL" sampleConfig === Just "mateusz@iohk.io"
  lookupGitConfig "GitHub.User" sampleConfig === Just "mgalazyn"

-- | Subsection names are case-sensitive per git specification.
-- remote.Origin.url must NOT match [remote "origin"].
prop_subsection_case_sensitive :: Property
prop_subsection_case_sensitive = H.propertyOnce $ do
  let config =
        T.unlines
          [ "[remote \"origin\"]"
          , "\turl = git@github.com:test/repo.git"
          ]
  -- Exact case matches
  lookupGitConfig "remote.origin.url" config === Just "git@github.com:test/repo.git"
  -- Wrong case for subsection does NOT match
  lookupGitConfig "remote.Origin.url" config === Nothing
  lookupGitConfig "remote.ORIGIN.url" config === Nothing

-- | Lines starting with # or ; are comments and are ignored.
prop_comments_ignored :: Property
prop_comments_ignored = H.propertyOnce $ do
  let configWithComments =
        T.unlines
          [ "[test]"
          , "# key = commented-out"
          , "; key = also-commented"
          , "\tkey = real-value"
          ]
  lookupGitConfig "test.key" configWithComments === Just "real-value"

-- | Distinct subsections (e.g. two remotes) are resolved independently.
prop_multiple_sections :: Property
prop_multiple_sections = H.propertyOnce $ do
  let config =
        T.unlines
          [ "[remote \"origin\"]"
          , "\turl = origin-url"
          , "[remote \"upstream\"]"
          , "\turl = upstream-url"
          ]
  lookupGitConfig "remote.origin.url" config === Just "origin-url"
  lookupGitConfig "remote.upstream.url" config === Just "upstream-url"
