"""A module defining the third party dependency OpenSSL"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def openssl_repositories():
    maybe(
        http_archive,
        name = "openssl",
        build_file = Label("//src/third_party/openssl:BUILD.openssl.bazel"),
        sha256 = "9384a2b0570dd80358841464677115df785edb941c71211f75076d72fe6b438f",
        strip_prefix = "openssl-1.1.1o",
        urls = [
            "https://starkware-third-party.s3.us-east-2.amazonaws.com/bazel/openssl/openssl-1.1.1o.tar.gz",
        ],
    )
    maybe(
        http_archive,
        name = "rules_perl",
        sha256 = "765e6a282cc38b197a6408c625bd3fc28f3f2d44353fb4615490a6eb0b8f420c",
        strip_prefix = "rules_perl-e3ed0f1727d15db6c5ff84f64454b9a4926cc591",
        urls = [
            "https://starkware-third-party.s3.us-east-2.amazonaws.com/bazel/perl/rules_perl-e3ed0f1727d15db6c5ff84f64454b9a4926cc591.tar.gz",
        ],
    )