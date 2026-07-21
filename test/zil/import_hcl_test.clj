(ns zil.import-hcl-test
  (:require [clojure.test :refer [deftest is testing]]
            [zil.core :as core]
            [zil.import.hcl :as ih]))

(defn- tmp-dir
  []
  (.toFile (java.nio.file.Files/createTempDirectory
            "zil-hcl-import"
            (make-array java.nio.file.attribute.FileAttribute 0))))

(deftest import-hcl-smoke-test
  (let [dir (tmp-dir)
        tf-file (java.io.File. dir "main.tf")]
    (spit tf-file "terraform {
  required_providers {
    aws = {
      source  = \"hashicorp/aws\"
      version = \"~> 5.0\"
    }
  }
}

provider \"aws\" {
  region = \"us-east-1\"
}

resource \"aws_instance\" \"web\" {
  ami           = \"ami-0abc\"
  instance_type = \"t3.micro\"
}

module \"network\" {
  source = \"./modules/network\"
}
")
    (let [report (ih/import-path->zil (.getAbsolutePath tf-file)
                                      {:module-name "hcl.import.demo"})
          zil-text (:text report)
          compiled (core/compile-program zil-text)
          provider-decls (filter #(= :provider (:kind %)) (:declarations compiled))
          queried (core/execute-program
                   (str zil-text
                        "\nQUERY resource_provider:\n"
                        "FIND ?p WHERE hcl_resource:aws_instance:web#provider@?p.\n"))]
      (is (:ok report))
      (is (= "hcl.import.demo" (:module report)))
      (is (= 1 (count provider-decls)))
      (is (= "provider:aws" (str "provider:" (-> provider-decls first :name))))
      (is (= [["provider:aws"]]
             (get-in queried [:queries "resource_provider" :rows]))))))

(deftest import-hcl-writes-output-when-requested-test
  (let [dir (tmp-dir)
        tf-file (java.io.File. dir "providers.tf")
        out-file (java.io.File. dir "imported.zc")]
    (spit tf-file "provider \"local\" {
  alias = \"default\"
}
resource \"local_file\" \"hello\" {
  filename = \"/tmp/hello.txt\"
}
")
    (let [report (ih/import-path->zil (.getAbsolutePath tf-file)
                                      {:module-name "hcl.import.write"
                                       :output-path (.getAbsolutePath out-file)})
          text (slurp out-file)]
      (is (:ok report))
      (is (.exists out-file))
      (is (re-find #"PROVIDER local" text))
      (is (re-find #"hcl_resource:local_file:hello#provider@provider:local" text)))))

(deftest import-hcl-rejects-missing-input-test
  (testing "No hcl/tf files in path"
    (let [dir (tmp-dir)]
      (is (thrown? clojure.lang.ExceptionInfo
                   (ih/import-path->zil (.getAbsolutePath dir)))))))
